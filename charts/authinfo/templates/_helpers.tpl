{{- define "authinfo.configChecksum" -}}
{{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end -}}
