{{/*
앱 이름
*/}}
{{- define "member.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
풀네임
*/}}
{{- define "member.fullname" -}}
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
{{- define "member.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
공통 레이블
*/}}
{{- define "member.labels" -}}
helm.sh/chart: {{ include "member.chart" . }}
{{ include "member.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{/*
셀렉터 레이블
*/}}
{{- define "member.selectorLabels" -}}
app.kubernetes.io/name: {{ include "member.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
