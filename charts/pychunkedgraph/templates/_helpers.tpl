{{- define "pcg_env.config" -}}
- name: MANIFEST_CACHE_REDIS_HOST
  value: "{{ .Values.pychunkedgraph.redis.host }}"
- name: REDISHOST
  value: "{{ .Values.pychunkedgraph.redis.host }}"
- name: AUTH_URI
  value: "{{ .Values.cluster.globalServer }}/auth"
- name: STICKY_AUTH_URL
  value: "{{ .Values.cluster.globalServer }}/sticky_auth"
- name: AUTH_URL
  value: "{{ .Values.cluster.globalServer }}/auth"
- name: BIGTABLE_PROJECT
  value: "{{ .Values.cluster.dataProjectName | default .Values.cluster.googleProject }}"
- name: BIGTABLE_INSTANCE
  value: "{{ .Values.pychunkedgraph.bigtableInstanceName}}"
- name: INFO_URL
  value: "{{ .Values.cluster.globalServer }}/info"
- name: REDIS_SERVICE_HOST
  value: "{{ .Values.pychunkedgraph.redis.host }}"
- name: REDIS_SERVICE_PORT
  value: "{{ .Values.pychunkedgraph.redis.port }}"
- name: APP_SETTINGS
  value: "pychunkedgraph.app.config.DevelopmentConfig"
- name: PROJECT_ID
  value: "{{ .Values.cluster.dataProjectName }}"
- name: SEGMENTATION_URL_PREFIX
  value: "segmentation"
- name: PROJECT_NAME
  value: "{{ .Values.cluster.googleProject }}"
- name: PYCHUNKEDGRAPH_EDITS_EXCHANGE
  value: "{{ .Values.cluster.cluster_prefix }}_PCG_EDIT"
- name: PYCHUNKEDGRAPH_EDITS_LOW_PRIORITY_EXCHANGE
  value: "{{ .Values.cluster.cluster_prefix }}_PCG_LOW_PRIORITY_REMESH"
- name: PCG_SERVER_LOGS_PROJECT
  value: "{{ .Values.cluster.googleProject }}"
- name: PCG_SERVER_LOGS_NS
  value: "pcg_server_logs_{{ .Values.cluster.cluster_prefix }}"
- name: PCG_SERVER_ENABLE_LOGS
  value: "{{ .Values.pychunkedgraph.enableLogs | default "enable"}}"
- name: PCG_SERVER_LOGS_LEAVES_MANY
  value: "{{ .Values.pychunkedgraph.logsLeavesMany }}"
- name: PCG_GRAPH_IDS
  {{- $gids := .Values.pychunkedgraph.graphIds -}}
  {{- if kindIs "slice" $gids }}
  value: "{{ join "," $gids }}"
  {{- else if $gids }}
  value: "{{ $gids }}"
  {{- else }}
  value: ""
  {{- end }}
- name: PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION
  value: "upb"
- name: ZSTD_THREADS
  value: "4"
- name: MESHING_URL_PREFIX
  value: "meshing"
- name: AUTH_USE_REDIS
  value: "false"
- name: DAF_CREDENTIALS
  value: "/home/nginx/.cloudvolume/secrets/cave-secret.json"
- name: LIMITER_CATEGORIES
  value: '{"query":"{{ .Values.pychunkedgraph.limitsQueryPerMinute | default 100}}/minute","fast_query":"{{ .Values.pychunkedgraph.limitsFastQueryPerMinute | default 2000}}/minute"}'
- name: LIMITER_URI
  value: "redis://{{ .Values.limiter.redis.host }}/0"
{{- end -}}

{{/*
Memory limit derived from a memory REQUEST, for containers whose request is a k8s quantity string
rather than the bare-Gb number readMemGb/writeMemGb use.

Why a ratio and not an absolute limit: a container with no memory limit does not fail in isolation
when it over-allocates -- it pushes the node past its eviction threshold and the kubelet evicts
pods, taking neighbours down with it. A limit turns that node-wide eviction into a contained
per-pod OOM kill. But a hand-set absolute limit rots the moment someone retunes the request, and
it is easy to set one low enough to crash-loop healthy pods or high enough to contain nothing.
Expressing it as a multiple of the request means the request stays the only number to touch.

Args: request (quantity string), ratio (number), name (values path, for error messages).
A ratio of 0 returns the empty string, so the caller emits no limit at all.

Normalises through bytes and emits Mi so any valid request unit (Mi, Gi, G, Ki, bare bytes) yields
a valid quantity, and 200Mi * 1.5 is 300Mi rather than a fractional-byte "0.3Gi" the API rejects.
*/}}
{{- define "pcg.memLimit" -}}
{{- $ratio := .ratio -}}
{{- if $ratio -}}
{{- $req := .request | toString -}}
{{- $num := regexFind "^[0-9.]+" $req -}}
{{- $unit := regexFind "[A-Za-z]*$" $req -}}
{{- if not $num -}}{{- fail (printf "pcg.memLimit: %s = %q is not a memory quantity" .name $req) -}}{{- end -}}
{{- $mult := 1.0 -}}
{{- if eq $unit "Ki" -}}{{- $mult = 1024.0 -}}
{{- else if eq $unit "Mi" -}}{{- $mult = 1048576.0 -}}
{{- else if eq $unit "Gi" -}}{{- $mult = 1073741824.0 -}}
{{- else if eq $unit "Ti" -}}{{- $mult = 1099511627776.0 -}}
{{- else if or (eq $unit "K") (eq $unit "k") -}}{{- $mult = 1000.0 -}}
{{- else if eq $unit "M" -}}{{- $mult = 1000000.0 -}}
{{- else if eq $unit "G" -}}{{- $mult = 1000000000.0 -}}
{{- else if eq $unit "T" -}}{{- $mult = 1000000000000.0 -}}
{{- else if ne $unit "" -}}{{- fail (printf "pcg.memLimit: %s = %q has an unrecognised unit %q" .name $req $unit) -}}
{{- end -}}
{{- printf "%dMi" (int64 (ceil (divf (mulf (float64 $num) $mult (float64 $ratio)) 1048576.0))) -}}
{{- end -}}
{{- end -}}

{{- define "pcg.uwsgiExporter" -}}
- name: uwsgi-exporter
  image: caveconnectome/uwsgi-export-workers:v14
  # Exposes the metrics endpoint on 0.0.0.0:9101
  ports:
    - containerPort: 9101
  env:
  # This tells the exporter where to find the uWSGI stats server
  - name: UWSGI_STATS_URL
    value: "http://localhost:9192"
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      cpu: 50m
      memory: 64Mi
  readinessProbe:
    httpGet:
      path: /
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
{{- end -}}

{{- define "sysctl.config" -}}
- name: sysctl-buddy
  image: alpine:3.4
  command:
    - /bin/sh
    - -c
    - |
      while true; do
        sysctl -w net.core.somaxconn=32768
        sysctl -w net.ipv4.ip_local_port_range='1024 65535'
        sleep 100
      done
  imagePullPolicy: IfNotPresent
  securityContext:
    privileged: true
  resources:
    requests:
      memory: 10Mi
      cpu: 5m
{{- end -}}
