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

Every pod running this image uses this. Modules read config at IMPORT time
(throttle.py builds a CeleryThrottle; task.py/monitor.py/upload build Redis
clients) which runs before any Flask app context exists, so get_config_param
cannot see config.cfg and falls through to os.environ. A pod missing one of
these fails at import, in that pod only, long after deploy -- which is how the
Ray head shipped without QUEUE_LENGTH_LIMIT and died on int(None).

Consolidating here also fixed three pieces of drift that had accumulated from
maintaining the same block in seven places by hand:

  * the api set QUEUE_LENGTH_LIMIT 5001 where everything else used 5000 (typo)
  * the api set no REDIS_* at all
  * consumer/producer set REDIS_HOST without REDIS_PORT or REDIS_PASSWORD

That divergence is exactly the failure mode a shared helper prevents, and it is
invisible until the one pod that needed the missing var runs the code path that
reads it.
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
  value: {{ .Values.cluster.bigtableInstance | default "" | quote }}
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
