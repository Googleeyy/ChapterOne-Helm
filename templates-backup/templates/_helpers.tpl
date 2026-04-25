{{/* vim: set filetype=mustache: */}}
{{/* Expand the name of the chart. */}}
{{- define "library-e2e.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "library-e2e.fullname" -}}
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

{{/* Create chart name and version as used by the chart label. */}}
{{- define "library-e2e.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "library-e2e.labels" -}}
helm.sh/chart: {{ include "library-e2e.chart" . }}
{{ include "library-e2e.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.global.environment }}
{{- end }}

{{/* Selector labels */}}
{{- define "library-e2e.selectorLabels" -}}
app.kubernetes.io/name: {{ include "library-e2e.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/* Create the name of the service account to use */}}
{{- define "library-e2e.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "library-e2e.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Internal DNS helper for backend services */}}
{{- define "library-e2e.backendDns" -}}
{{- printf "%s.%s.svc.cluster.local" .serviceName .Values.global.environment -}}
{{- end }}

{{/* MongoDB URI helper */}}
{{- define "library-e2e.mongoUri" -}}
{{- printf "mongodb://mongo-svc.%s.svc.cluster.local:27017/%s" .Values.global.environment .database -}}
{{- end }}

{{/* Service name helper */}}
{{- define "library-e2e.serviceName" -}}
{{- printf "%s-svc" .serviceRoot -}}
{{- end }}
