{{/*
앱 이름
*/}}
{{- define "document.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
풀네임
*/}}
{{- define "document.fullname" -}}
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
Chart 레이블
*/}}
{{- define "document.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
공통 레이블
*/}}
{{- define "document.labels" -}}
helm.sh/chart: {{ include "document.chart" . }}
{{ include "document.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{/*
셀렉터 레이블
*/}}
{{- define "document.selectorLabels" -}}
app.kubernetes.io/name: {{ include "document.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
