{{/*
Shared env blocks for pods running the materializationengine image.

*/}}

{{/*
materializationengine.baseEnv -- the config/credential/auth env that is
IDENTICAL in every pod running this image.

Membership here is not a judgement call: these six were verified to render the
same value in all eight app containers before this helper existed. Anything that
varies per pod stayed in its own template rather than being averaged into a
shared default -- see the note on redisEnv/throttleEnv below.

Does NOT include per-workload settings (QUEUE_NAME, WORKER_NAME, CELERY_*).

Usage:
    env:
      {{- include "materializationengine.baseEnv" . | nindent 12 }}
      - name: QUEUE_NAME
        value: my-queue
*/}}
{{- define "materializationengine.baseEnv" -}}
- name: MATERIALIZATION_ENGINE_SETTINGS
  value: /app/materializationengine/instance/config.cfg
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: /home/nginx/.cloudvolume/secrets/google-secret.json
- name: DAF_CREDENTIALS
  value: /home/nginx/.cloudvolume/secrets/cave-secret.json
- name: AUTH_URI
  value: {{ .Values.cluster.globalServer }}/auth
- name: AUTH_URL
  value: {{ .Values.cluster.globalServer }}/auth
- name: STICKY_AUTH_URL
  value: {{ .Values.cluster.globalServer }}/sticky_auth
{{- end -}}

{{/*
materializationengine.appEnv -- baseEnv plus the full Redis and throttle sets.

SCOPE: the Ray job template ONLY. The api and celery templates deliberately keep
their own inline env blocks.

These helpers were briefly applied to all seven workload templates. That is
reverted: consolidating them changed four pods' environments at once, and the
resulting deployment problems were not worth absorbing alongside a new feature.
The Ray templates keep using them because they are new -- nothing regresses if
they are wrong, and the Ray head is the pod that most needs the full set.

Why the full set matters here: several modules read config at IMPORT time
(throttle.py builds a CeleryThrottle; task.py/monitor.py/upload build Redis
clients), which runs before any Flask app context exists, so get_config_param
cannot see config.cfg and falls through to os.environ. A pod missing one of
these fails at import, in that pod only, long after deploy -- which is exactly
how the Ray head shipped without QUEUE_LENGTH_LIMIT and died on int(None).

Known divergence in the templates that are NOT using this (left alone on
purpose, recorded so it is not rediscovered):

  * the api sets QUEUE_LENGTH_LIMIT 5001 where everything else uses 5000
  * the api sets no REDIS_* at all
  * consumer/producer set REDIS_HOST without REDIS_PORT or REDIS_PASSWORD

If those are ever unified, do it as its own change with its own rollout, not as
a side effect of something else.
*/}}
{{- define "materializationengine.appEnv" -}}
{{- include "materializationengine.baseEnv" . }}
{{- include "materializationengine.redisEnv" . }}
{{- include "materializationengine.throttleEnv" . }}
{{- end -}}

{{/*
materializationengine.redisEnv -- Redis coordinates.

REDIS_SERVICE_HOST duplicates REDIS_HOST because both names are read in
different places in the codebase; dropping either silently breaks one of them.
*/}}
{{- define "materializationengine.redisEnv" -}}
{{- $redis := .Values.materialize.redis | default dict }}
- name: REDIS_HOST
  value: {{ $redis.host | quote }}
- name: REDIS_SERVICE_HOST
  value: {{ $redis.host | quote }}
- name: REDIS_PORT
  value: {{ $redis.port | default 6379 | quote }}
- name: REDIS_PASSWORD
  value: {{ $redis.password | default "" | quote }}
{{- end -}}

{{/*
materializationengine.throttleEnv -- celery backpressure knobs.

Required even by pods that never throttle anything, because throttle.py builds a
module-level CeleryThrottle at import time -- before any Flask app context
exists, so get_config_param falls through to os.environ and int(None) raises.

throttleQueues defaults true, matching what every celery pod already set. The
Ray driver inherits it and does not care: it produces onto no celery queue, so
throttle_celery is constructed and never consulted.
*/}}
{{- define "materializationengine.throttleEnv" -}}
{{- $m := .Values.materialize | default dict }}
- name: QUEUE_LENGTH_LIMIT
  value: {{ dig "queueLengthLimit" 5000 $m | quote }}
- name: QUEUES_TO_THROTTLE
  value: {{ dig "queuesToThrottle" "process" $m | quote }}
- name: THROTTLE_QUEUES
  value: {{ dig "throttleQueues" true $m | quote }}
{{- end -}}

{{/*
materializationengine.dataEnv -- backing-store coordinates and CloudVolume tuning.

Not celery-specific despite one unfortunate name: CELERY_CLOUDVOLUME_CACHE_BYTES
sizes the CloudVolume cache, and any pod that touches segmentation data wants it
along with the Bigtable target and the pychunkedgraph read endpoint.
*/}}
{{- define "materializationengine.dataEnv" -}}
{{- $m := .Values.materialize | default dict }}
- name: BIGTABLE_PROJECT
  value: {{ .Values.cluster.bigtableProject | default .Values.cluster.googleProject | quote }}
- name: BIGTABLE_INSTANCE
  # same default as the celery templates (and terraform's bigtable_instance_name):
  # empty made root id lookups ask for projects/<p>/instances//tables/<pcg table>
  value: {{ .Values.cluster.bigtableInstance | default "pychunkedgraph" | quote }}
- name: LOCAL_SERVER_URL
  value: {{ dig "pychunkedgraphReadServiceUrl" "http://pychunkedgraph-read-service/" $m | quote }}
- name: CLOUDVOLUME_PARALLEL
  value: {{ dig "cloudvolumeParallel" 10 $m | quote }}
- name: CELERY_CLOUDVOLUME_CACHE_BYTES
  value: {{ dig "cloudvolumeCacheBytes" 100000000 $m | quote }}
{{- end -}}

{{/*
materializationengine.cloudsqlProxyEnv -- the cloud-sql-proxy sidecar's own env.

Separate from appEnv: it configures the proxy container, not the app.
*/}}
{{- define "materializationengine.cloudsqlProxyEnv" -}}
- name: CSQL_PROXY_HEALTH_CHECK
  value: "true"
- name: CSQL_PROXY_HTTP_PORT
  value: "9801"
- name: CSQL_PROXY_HTTP_ADDRESS
  value: 0.0.0.0
- name: CSQL_PROXY_QUITQUITQUIT
  value: "true"
- name: CSQL_PROXY_ADMIN_PORT
  value: "9092"
- name: CSQL_PROXY_STRUCTURED_LOGS
  value: "true"
{{- end -}}


{{/*
Switch to the nginx user without staying in the process tree. `su nginx -c` stays as the
parent: on SIGTERM it forwards the signal and exits about 2 seconds later, and as the
container's main process its exit ends the container, killing celery mid warm shutdown
whatever terminationGracePeriodSeconds is (ltv7 transfer_to_production, 2026-10-06).
setpriv execs the command, so celery itself receives SIGTERM and drains its tasks. su
used to set HOME, which cloudvolume needs to find ~/.cloudvolume/secrets.
*/}}
{{- define "materializationengine.asNginx" -}}
env HOME=/home/nginx USER=nginx LOGNAME=nginx setpriv --reuid=nginx --regid=nginx --init-groups
{{- end }}


{{/*
materializationengine.rayCloudsqlProxy -- the cloud-sql-proxy native sidecar of Ray
pods (head, and workers that reach the database), as an initContainers list item.
Authenticates with the Ray service account key (ray-google-cloud-key).
*/}}
{{- define "materializationengine.rayCloudsqlProxy" -}}
- name: cloudsql-proxy
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.23.0
  restartPolicy: Always
  args:
    - "--port=3306"
    - "--credentials-file=/secrets/cloudsql/google-secret.json"
    - "--max-sigterm-delay=3600s"
    - "{{ .Values.cloudsql.projectId | default .Values.cluster.googleProject }}:{{ .Values.cluster.googleRegion }}:{{ .Values.cloudsql.sqlInstanceName }}"
  env:
    {{- include "materializationengine.cloudsqlProxyEnv" . | nindent 4 }}
  ports:
    - containerPort: 9801
      protocol: TCP
  resources:
    requests:
      memory: 8Mi
      cpu: 10m
  securityContext:
    runAsUser: 2
    allowPrivilegeEscalation: false
  startupProbe:
    httpGet: { path: /startup, port: 9801, scheme: HTTP }
    failureThreshold: 60
    periodSeconds: 1
    timeoutSeconds: 10
  volumeMounts:
    - name: google-cloud-key
      mountPath: /secrets/cloudsql
      readOnly: true
  lifecycle:
    preStop:
      exec:
        command: ["sh", "-c", "curl -f -X POST http://localhost:9092/quitquitquit || kill -15 1"]
{{- end -}}

{{/*
materializationengine.rayUploadEnv -- settings of the bulk upload RayJob driver and its
workers (ray.upload). Empty unless ray.upload is on.
*/}}
{{- define "materializationengine.rayUploadEnv" -}}
{{- $ray := .Values.ray | default dict }}
{{- if $ray.upload }}
- name: UPLOAD_STATE_DATABASE
  value: {{ dig "uploadStateDatabase" "upload_state" .Values.materialize | quote }}
- name: UPLOAD_RAY_MAX_IN_FLIGHT
  value: {{ $ray.uploadMaxInFlight | default 32 | quote }}
{{- with $ray.uploadFaultInject }}
# Testing only: the driver exits at this point (e.g. "after:upload_to_db",
# "spatial_chunk:200") as a lost head pod would.
- name: UPLOAD_FAULT_INJECT_ENABLED
  value: "true"
- name: UPLOAD_FAULT_INJECT
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end -}}
