# 모니터링 (Prometheus, Grafana)

노드와 실습 세션(`lab-*` namespace)의 CPU·메모리를 7일 동안 보는 구성이다([ADR 026](../decisions/026-관리와-기록.md)). `kube-prometheus-stack` 차트를 가볍게 설치한다. Alertmanager는 없고, 수집 30초, 보존 7일이다. 값은 [k8s/monitoring-values.yaml](k8s/monitoring-values.yaml)에 있다.

| 구성요소 | 하는 일 |
|---|---|
| Prometheus | 지표 수집과 저장. 저장은 기본 StorageClass(local-path)의 PVC 5Gi |
| Grafana | 대시보드. 외부에 열지 않고 관리자가 port-forward로 접속 |
| kubelet(cAdvisor) | 컨테이너별 CPU·메모리. 실습 Pod 안에서 compose로 띄운 서비스(web, db)별 값은 보이지 않음 |
| node-exporter | 노드 CPU·메모리·디스크 |
| kube-state-metrics | Pod 재시작, OOMKilled, 자원 요청·한도 |
| Prometheus Operator | Prometheus 설정 관리 |

## 설치

관리자 kubeconfig로 관리 PC에서 한다. 전제: [cluster-setup.md](cluster-setup.md) 9절 local-path-provisioner(기본 StorageClass), Helm 4.

```bash
KC=~/.kube/<클러스터이름>.yaml
K="kubectl --kubeconfig $KC"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

$K create namespace monitoring
# Grafana 관리자 비밀번호는 무작위로 만들어 Secret에만 둔다. 화면이나 로그, 저장소에 남기지 않는다
$K -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.22.0 \
  --namespace monitoring --kubeconfig $KC -f infra/k8s/monitoring-values.yaml --wait --timeout 10m
$K -n monitoring get pods   # 5개 모두 Running
```

- 값을 바꾸면 같은 `helm upgrade --install`을 다시 실행
- 지우기: `helm uninstall monitoring -n monitoring --kubeconfig $KC` 뒤 `$K delete namespace monitoring`(PVC와 저장한 지표도 지워짐)
- 차트가 만드는 CRD는 `helm uninstall`로 지워지지 않음. 다시 설치할 때는 그대로 둬도 됨

## 접속

```bash
$K -n monitoring port-forward svc/monitoring-grafana 3000:80
# 브라우저로 http://127.0.0.1:3000, 사용자 admin
# 비밀번호는 필요할 때 직접 꺼낸다(출력을 남기지 않는 터미널에서)
$K -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

| 보고 싶은 것 | 대시보드 |
|---|---|
| namespace(실습 세션)별 CPU·메모리 한눈에 | Kubernetes / Compute Resources / Cluster |
| 실습 세션 하나(`lab-<세션 id>`) | Kubernetes / Compute Resources / Namespace (Pods), namespace 선택 |
| 노드 전체 | Node Exporter / Nodes |
| OOMKilled, 재시작 | Kubernetes / Compute Resources / Pod |

- 익명 접근은 막혀 있음(로그인 없이 API 요청하면 401), 가입 화면 없음
- 운영 서버에서 Grafana를 공개하는 방식은 HTTPS(#74) 뒤에 정함. 그때까지 port-forward로만 접속

## 자원 사용량

2026-11-22 개발 클러스터에서 설치 후 약 10분, 실습 세션 1개를 띄운 상태에서 Prometheus로 잰 값이다. 수집 중인 series 약 5만 개.

| Pod | 메모리(working set) |
|---|---|
| Grafana(본체와 대시보드·데이터 원본 sidecar 2개) | 433MiB(sidecar가 각각 약 80MiB) |
| Prometheus | 232MiB |
| Prometheus Operator | 40MiB |
| kube-state-metrics | 21MiB |
| node-exporter | 9MiB |
| 합계 | 약 740MiB |

- CPU는 안정된 뒤 합쳐 약 0.06 core. 처음 뜰 때 Grafana가 대시보드를 넣는 동안 잠깐 많이 씀
- 메모리 4GB 노드에서는 실습 세션 2개(각 한도 512Mi)와 함께 두기 빠듯함(설치 뒤 노드의 사용 가능 메모리 약 1.1GB). 운영 서버(메모리 32GB 예정)에서는 여유가 있음
- 디스크는 Prometheus PVC 5Gi 안에서 보존 7일 또는 4GB 중 먼저 닿는 쪽까지 씀

## 알려진 함정

- Grafana 메모리 한도를 256Mi로 두면 처음 뜰 때 대시보드를 넣다가 한도에 닿아 시간 초과로 재시작하고, 뜬 뒤에도 CPU를 계속 씀. 512Mi로 둠
- Alertmanager를 꺼도 Grafana 데이터 원본에 Alertmanager가 남는다. values의 `grafana.sidecar.datasources.alertmanager.enabled: false`로 빼고, 이미 떠 있는 Grafana는 `$K -n monitoring rollout restart deploy/monitoring-grafana`로 다시 띄워야 사라짐(Grafana 안 DB에 남아 있어서)
- kubeadm은 etcd, scheduler, controller-manager, kube-proxy 지표를 127.0.0.1에만 열어서 수집하지 못한다. values에서 꺼 둠(켜 두면 target down만 남음)
- Prometheus 이미지에는 `wget`, `curl`이 없다. 쿼리를 손으로 보려면 `svc/monitoring-kube-prometheus-prometheus` 9090으로 port-forward한다
