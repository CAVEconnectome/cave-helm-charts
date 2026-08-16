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
