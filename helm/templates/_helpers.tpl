{{/*
Expand the name of the chart.
*/}}
{{- define "perfsonar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "perfsonar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "perfsonar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "perfsonar.labels" -}}
helm.sh/chart: {{ include "perfsonar.chart" . }}
{{ include "perfsonar.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{- define "perfsonar.postgresPVC" }}
- name: postgresql-data
  persistentVolumeClaim:
    claimName: {{ .Release.Name }}-postgres-pvc
{{- end }}

{{- define "perfsonar.postgresMount" }}
- name: postgresql-data
  mountPath: /var/lib/postgresql
{{- end }}



{{/*
Selector labels
*/}}
{{- define "perfsonar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "perfsonar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "perfsonar.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "perfsonar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
