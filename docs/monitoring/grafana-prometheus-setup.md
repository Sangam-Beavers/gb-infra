# Grafana / Prometheus 모니터링 스택 구축 (stage)

> 운영자 콘솔(admin, "Operator Web Console")의 **Monitoring 탭 Grafana 임베드**를 실제로 띄우기 위한
> 모니터링 스택 설치·설정 스펙. **전부 in-cluster(Prometheus scrape)** 로 구성하며 CloudWatch는 사용하지 않는다.
> GitOps(ArgoCD)로 먼저 배포하고, 이 문서의 스펙대로 추후 **Terraform `helm_release`** 로 한 번에 이행한다.
>
> 대상 클러스터: `sb-stage-eks` · 작성 시점 환경: stage
> 미정 값은 `TODO(배포 후 채움)` 으로 표기 — 실제 배포하며 확정한다.

---

## 0. 배경 / 현재 상태

- admin-service 콘솔의 Monitoring 탭은 Grafana 대시보드 5종 + ArgoCD를 **iframe 임베드**하도록 설계돼 있다.
  현재 `GRAFANA_BASE_URL`/`ARGOCD_BASE_URL` 이 `localhost` placeholder라 임베드가 빈 화면이다.
- stage 클러스터에 **Grafana/Prometheus가 아직 없다**(`kubectl get svc,ingress -A | grep -iE grafana|prometheus` → 0건).
- 6개 백엔드 서비스(member·wallet·community·document·admin·app-admin)는 모두 `micrometer-registry-prometheus`
  의존성을 갖고 `/actuator/prometheus` 를 노출한다(= ServiceMonitor만 붙이면 즉시 수집 가능).

## 1. 구성요소

| 구성요소 | 역할 | 노출 |
|---|---|---|
| **kube-prometheus-stack** | Prometheus Operator · Prometheus · Grafana · Alertmanager · node-exporter · kube-state-metrics | Grafana=내부 ALB / 나머지=ClusterIP |
| **ServiceMonitor × 6** | 각 Spring 서비스 `/actuator/prometheus` 스크레이프 | — |
| **redis_exporter** | 직접 띄운 Redis 메트릭 수집(→ Prometheus) | ClusterIP + ServiceMonitor |

> MSA 원칙: 각 서비스가 **자기 메트릭만** `/actuator/prometheus` 로 노출하고, Prometheus가 ServiceMonitor로
> 수집한다. 모니터링 스택은 별도 네임스페이스로 격리한다(앱 워크로드와 분리).

## 2. 네임스페이스 / 노출 정책

- **네임스페이스: `monitoring`** (전용, 격리).
- **Grafana**: 내부 ALB Ingress(`alb`, `internal` scheme) — 운영자 브라우저 접근용. admin 콘솔과 동일한 내부망.
  - 임베드 주소(`GRAFANA_BASE_URL`)는 이 ALB 호스트가 된다. `TODO(배포 후 채움): internal-...elb.amazonaws.com`
- **Prometheus · Alertmanager**: ClusterIP(외부 노출 없음). Grafana가 in-cluster로 질의.

## 3. Grafana 설정 (임베드가 핵심)

Grafana는 기본적으로 iframe 임베드를 차단하고 로그인을 요구한다. admin 콘솔에서 인라인 임베드되려면:

```yaml
# kube-prometheus-stack values: grafana.grafana.ini
grafana:
  grafana.ini:
    security:
      allow_embedding: true          # iframe 허용 (기본 X-Frame-Options deny 해제)
      # cookie_samesite: none        # 크로스사이트 쿠키 필요 시(HTTPS 전제)
    auth.anonymous:
      enabled: true                  # 로그인 벽 제거 — 내부 전용이라 익명 허용
      org_role: Viewer               # 읽기 전용
```

- **익명 Viewer 사유**: 콘솔이 내부 ALB로만 접근 가능(인터넷 비노출)하고 admin 자체가 로그인 없는 내부 도구라,
  임베드 iframe에 로그인 화면이 뜨지 않게 익명 뷰어를 허용한다. (보안 경계 = 내부망 + ALB)
- Datasource: kube-prometheus-stack이 Prometheus를 자동 연결.

### 3-1. 대시보드 (UID 고정 — admin 콘솔과 일치 필수)

admin 콘솔은 다음 UID로 임베드 URL을 만든다. Grafana에 **동일 UID**로 프로비저닝해야 한다.

| label | UID (고정) | 출처 | 도입 |
|---|---|---|---|
| Kubernetes Cluster | `kubernetes-cluster` | kube-state-metrics / node-exporter | ✅ 지금 |
| JVM Micrometer | `jvm-micrometer` | 서비스 `/actuator/prometheus` | ✅ 지금 |
| Spring Boot HTTP | `spring-boot-statistics` | 서비스 `/actuator/prometheus` | ✅ 지금 |
| Redis | `redis` | redis_exporter | ✅ 지금 |
| ~~AWS RDS~~ | ~~`aws-rds`~~ | ~~CloudWatch~~ | ❌ **보류**(§7) — admin 콘솔에서도 제거 |

> 대시보드 import 시 JSON의 `uid` 필드를 위 값으로 **명시 고정**한다(자동 생성 UID면 임베드 URL이 깨짐).
> grafana.com 대시보드 ID 예시는 배포 시 확정해 기록한다: `TODO(배포 후 채움)`.

## 4. 메트릭 수집 — ServiceMonitor

대상 6서비스 모두 동일 패턴(포트 `http`, path `/actuator/prometheus`). label selector로 일괄 처리.

```yaml
# 예시(서비스별 또는 공통 selector)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gb-spring-services
  namespace: monitoring
  labels: { release: kube-prometheus-stack }   # Prometheus가 이 label로 SM을 픽업
spec:
  namespaceSelector:
    matchNames: ["sb-stage-app-ns"]
  selector:
    matchExpressions:
      - { key: app, operator: In, values: [member, wallet, community, document, admin, app-admin] }
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
```

- 확인 필요: `document` 서비스의 actuator `exposure.include` 에 `prometheus` 포함 여부(나머지 5개는 확인됨).
  미포함 시 `application-stage.yml` 에 추가. `TODO(확인)`

## 5. Redis 메트릭 — redis_exporter → ElastiCache

stage Redis는 **ElastiCache**(외부 관리형, 인클러스터 아님)다. 단 **CloudWatch는 불필요** — `redis_exporter`가
Redis 프로토콜로 ElastiCache 엔드포인트에 **직접 접속**해 긁는다(인클러스터 exporter → ElastiCache). RDS와 달리
이 우회가 가능해 IRSA/CloudWatch 없이 in-cluster로 끝난다.

- 구성: `redis_exporter` Deployment + Service(monitoring NS) + ServiceMonitor.
- **시크릿 재사용**: 기존 `sb/stage/redis/auth` 를 ExternalSecret으로 끌어와 매핑(신규 시크릿 없음 — mcp-community가
  community DB 시크릿 재사용한 것과 동일 패턴).
  - `auth_token` → `REDIS_PASSWORD`
  - `primary_host` → `REDIS_HOST`, `port` → `REDIS_PORT`
  - `REDIS_ADDR = rediss://$(REDIS_HOST):$(REDIS_PORT)` (ElastiCache 전송중 암호화 `tls=true` → `rediss://`).
    인증서 검증 이슈 시 `REDIS_EXPORTER_SKIP_TLS_VERIFICATION=true`.
- 네트워크: 클러스터 → ElastiCache는 이미 member/wallet이 접속 중이라 SG/VPC 도달성 확보됨.
- 클러스터 모드: 시크릿이 `primary_host`(단일) → cluster-mode disabled(primary/replica)로 보이므로 단일 엔드포인트로 충분.
- 대시보드 UID `redis` 와 연결.

> **config 거버넌스 노트 (Terraform 담당 확인)**: admin의 `GRAFANA_BASE_URL`·`ARGOCD_BASE_URL`은
> **비밀이 아니라** values-stage.yaml(Git/ConfigMap)에 직접 둔다 — admin의 다른 서비스 URL(`MEMBER_INTERNAL_URL` 등)과
> 동일한 성격. 다만 환경별 인프라 엔드포인트이므로, **Terraform 버전에선 Cognito issuer처럼 Parameter Store로 이관**하는
> 것을 검토 권장(SM은 비밀 전용이라 대상 아님). 현재는 박아두고 진행.

## 6. admin 콘솔 연동 (값 교체 + 정리)

1. **admin 차트** `charts/admin/values-stage.yaml`:
   - `grafanaBaseUrl` = Grafana 내부 ALB 주소(§2). `TODO`
   - `argocdBaseUrl` = ArgoCD UI 주소(브라우저로 여는 그 주소). `TODO`
2. **admin-service** `application.yaml` 의 `admin.monitoring.embeds.grafana.dashboards` 에서 **`aws-rds` 항목 제거**.
3. 반영: gb-infra push → ArgoCD sync → `kubectl -n sb-stage-app-ns rollout restart deploy/admin`
   (ConfigMap 변경은 파드 자동 재시작 안 됨).

> **인라인 임베드 vs 새 창**: §3 설정이 끝나면 iframe 인라인이 뜬다. ArgoCD는 온프렘 + iframe 차단이라
> 인라인 임베드가 까다로우니 **ArgoCD는 "새 창에서 열기"만** 사용하는 것을 권장(URL만 맞추면 동작).

## 7. 보류 — AWS RDS(Aurora) CloudWatch 대시보드

Aurora는 RDS의 한 엔진이므로 CloudWatch에 RDS 지표가 있으나, 이 대시보드는 **현재 도입하지 않는다**:

- **AWS IAM(IRSA)** 필요 → 크로스팀/Terraform 의존
- **CloudWatch API 비용**(GetMetricData 과금)
- Prometheus scrape와 다른 별도 파이프라인 → in-cluster 구성의 단순함을 해침

향후 DB 메트릭이 필요하면 **CloudWatch보다 `mysqld_exporter`(in-cluster, IAM 불필요)** 가 더 쉬운 대안.
도입 시 별도 섹션으로 추가한다.

## 8. 배포 — 수동 helm 설치 (interim) + Terraform 인계

### 8-0. 왜 ArgoCD가 아니라 수동 helm인가 (중요 — Terraform 담당 읽을 것)

ArgoCD의 **sb-stage-eks 클러스터 연결이 namespaced mode** (`NAMESPACES: sb-stage-app-ns` 한정)로
등록돼 있다. 이 모드에서는 **클러스터 전역 리소스(CRD·ClusterRole·Admission Webhook)를 만들 수 없다.**
kube-prometheus-stack은 이들이 필수라 ArgoCD 경로로는 배포 불가(`"cluster level CRD can not be managed
when in namespaced mode"` 에러). admin·community 등 앱은 네임스페이스 리소스뿐이라 영향 없었음.

→ 보안 경계(앱용 namespaced 연결)는 그대로 두고, **인프라 레벨인 모니터링 스택만 cluster-admin 권한으로
직접 설치**한다. 아래 명령이 SSOT이며, **Terraform 담당은 이를 `helm_release`(§9)로 코드화**하면 된다.

### 8-1. 사전조건
- 설치자 kubeconfig가 **sb-stage-eks + cluster-admin** (확인: `kubectl auth can-i create customresourcedefinitions` → yes).
- chart 버전: kube-prometheus-stack **`86.2.2`** (`charts/monitoring-stack/Chart.yaml`).

### 8-2. 실행 명령 (실제로 친 것 그대로)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cd gb-infra/charts/monitoring-stack
helm dependency build                                  # kube-prometheus-stack 86.2.2 vendoring
helm install monitoring-stack . -n monitoring --create-namespace
```
- 릴리스명 `monitoring-stack`, 네임스페이스 **`monitoring`**(전용. ArgoCD 제약 없으니 격리 복원).
- 우리 래퍼 차트가 kube-prometheus-stack + ServiceMonitor(`gb-spring-services`) + redis_exporter +
  대시보드를 한 번에 설치.

### 8-3. 검증
```bash
kubectl -n monitoring get pods                         # prometheus·grafana·operator·exporters Running
kubectl -n monitoring get ingress                      # Grafana 내부 ALB 주소
```
- 배포 후 실값:
  - Grafana ELB 주소 = `internal-k8s-monitori-monitori-c176229a39-1932184299.ap-northeast-2.elb.amazonaws.com` (내부 ALB)
  - 대시보드 실제 UID (admin 임베드에 반영 완료):
    - Kubernetes(Compute Resources/Cluster) = `efa86fd1d0c121a26444b636a3f509a8`
    - JVM(Micrometer) = `0829a2c7-6bad-4fc7-97b9-badb9568c87e`
    - Spring(Java SpringBoot APM) = `X09JGT7Gz`
    - Redis(Prometheus Redis Exporter 1.x) = `e008bc3f-81a2-40f9-baf2-a33fd8dec7ec`
    - AWS RDS = 제거(미도입)

### 8-4. 업그레이드 / 삭제 (참고)
```bash
helm upgrade monitoring-stack . -n monitoring          # values 변경 반영
helm uninstall monitoring-stack -n monitoring          # 제거(CRD는 helm이 안 지움 — 수동 정리 필요 시 kubectl delete crd ...)
```

## 9. Terraform 이행 (나중에 한 번에)

이 문서의 스펙을 그대로 Terraform으로 옮긴다.

```hcl
# 개략
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "86.2.2"         # §8-1과 동일 (charts/monitoring-stack/Chart.yaml)
  namespace  = "monitoring"
  create_namespace = true
  values     = [file("values/kube-prometheus-stack.stage.yaml")]   # §3 그대로
}

resource "helm_release" "redis_exporter" {
  name = "prometheus-redis-exporter"; chart = "prometheus-redis-exporter"; namespace = "monitoring"
  # REDIS_ADDR 등 §5
}

# ServiceMonitor / 대시보드 = kubernetes_manifest 또는 helm values 내 inline
# (RDS CloudWatch 도입 시) aws_iam_role(IRSA) + helm_release "cloudwatch-exporter"
```

- AWS 사전요소: ALB는 Ingress가 자동 생성. (RDS CloudWatch 도입 시에만) CloudWatch read IRSA 추가.

## 10. 검증 체크리스트 (배포 후)

- [ ] `kubectl -n monitoring get pods` — prometheus/grafana/exporters Running
- [ ] Grafana 내부 ALB 주소 브라우저 접근 → 익명 뷰어로 대시보드 열림
- [ ] Prometheus Targets에 6서비스 + redis_exporter UP
- [ ] 대시보드 UID 4종이 admin 콘솔 임베드 URL과 일치
- [ ] admin 콘솔 Monitoring 탭에서 iframe 인라인 표시(빈 화면 아님)
- [ ] admin 콘솔에서 AWS RDS 카드 사라짐

---

### 변경 이력
- v0.1 (작성) — 스코프 확정(in-cluster 4종, RDS CloudWatch 보류). 배포 후 실값으로 갱신 예정.
