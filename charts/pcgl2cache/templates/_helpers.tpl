{{/* Join helper for comma-separated lists etc. */}}
{{- define "pcgl2cache.join" -}}
{{- join "," . -}}
{{- end -}}

{{/*
Memory limit for a container.

Returns the explicit value when one is given, otherwise ratio x request. Kubernetes
quantities are strings, so the request is parsed here; Mi and Gi are supported because
those are what this chart's values use. Anything else fails the render rather than
silently producing a wrong limit.

usage:
  {{ include "pcgl2cache.memLimit" (dict "request" <req> "explicit" <limit|nil> "ratio" <ratio|nil>) }}
*/}}
{{/*
pcgl2cache.rssLimitSoft -- uwsgi's worker-spawn memory ceiling, in BYTES,
derived from the container's own memory limit.

The image's uwsgi.ini ships `cheaper-rss-limit-soft = 6442450944` (6 GiB): keep
spawning workers, 8 at a time up to `processes = 64`, until total RSS reaches
6 GiB. That number is meaningful only if the container may actually use 6 GiB.
With the chart's default limit of 1350Mi it is 4.8x too high, so under sustained
load uwsgi spawns straight past the cgroup limit and the pod is OOMKilled -- over
and over, which is what happened on minniev7 (50+ restarts/pod, all exit 137).

Deriving it from the limit is the whole point: the two numbers are the same
decision expressed twice, and any hardcoded value silently rots the moment
someone retunes resources.

The fraction leaves headroom for what is NOT uwsgi workers -- the master, nginx,
and the interpreter -- measured at ~814Mi idle against a 1350Mi limit on this
deployment. uwsgi checks this ceiling BEFORE spawning, so the check must trip
while there is still room for the workers already running to grow.

Takes: dict with "limit" (a Mi/Gi quantity) and optional "fraction".
*/}}
{{- define "pcgl2cache.rssLimitSoft" -}}
{{- $lim := .limit | toString -}}
{{- $frac := .fraction | default 0.75 -}}
{{- $mib := 0.0 -}}
{{- if hasSuffix "Gi" $lim -}}
{{- $mib = mulf (trimSuffix "Gi" $lim | float64) 1024.0 -}}
{{- else if hasSuffix "Mi" $lim -}}
{{- $mib = trimSuffix "Mi" $lim | float64 -}}
{{- else -}}
{{- fail (printf "pcgl2cache.rssLimitSoft: cannot derive from limit %q (expected Mi or Gi)" $lim) -}}
{{- end -}}
{{- mulf $mib $frac 1048576.0 | int64 -}}
{{- end -}}

{{- define "pcgl2cache.memLimit" -}}
{{- if .explicit -}}
{{- .explicit -}}
{{- else -}}
{{- $req := .request | toString -}}
{{- $ratio := .ratio | default 1.5 -}}
{{- if hasSuffix "Gi" $req -}}
{{- mulf (trimSuffix "Gi" $req | float64) $ratio 1024 | int -}}Mi
{{- else if hasSuffix "Mi" $req -}}
{{- mulf (trimSuffix "Mi" $req | float64) $ratio | int -}}Mi
{{- else -}}
{{- fail (printf "pcgl2cache.memLimit: cannot derive a limit from request %q (expected Mi or Gi); set an explicit resources.limits.memory instead" $req) -}}
{{- end -}}
{{- end -}}
{{- end -}}
