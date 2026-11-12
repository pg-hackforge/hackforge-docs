# 테스트 문제 이미지

실습 환경 기능(#6)을 확인할 때 쓰는 Challenge 이미지다. nginx와 PostgreSQL 두 서비스를 Docker Compose로 띄우고, 취약점이나 문제 내용은 없다. 실제 Challenge 형식과 첫 문제는 #7(Challenge 형식과 첫 문제(SQLi))에서 정하고, 이 이미지는 Pod 생성, Ready 판단, 자원 측정, 보안 확인에만 쓴다. 구조는 [ADR 012](../../decisions/012-실습-환경-수명-주기.md)의 서비스 이미지 tar 방식을 따른다.

| 파일 | 내용 |
|---|---|
| `Dockerfile` | `docker:dind` 위에 compose 파일, 서비스 이미지 tar, 시작 스크립트를 넣음 |
| `app/compose.yaml` | 서비스 정의. 이미지는 tar에서 load하므로 `pull_policy: never` |
| `hackforge/entrypoint.sh` | inner dockerd 시작, `images.tar` load, `docker compose up -d`. 단계별 시각을 로그에 남김 |
| `hackforge/ready.sh` | readinessProbe. compose 서비스가 모두 running이고 healthcheck가 있으면 healthy일 때 성공 |
| `build.sh` | 서비스 이미지를 `images.tar`로 묶고 Challenge 이미지를 빌드해 import할 tar로 저장 |
| `check.yaml` | 확인용 namespace, NetworkPolicy, ResourceQuota, Pod. 백엔드가 세션마다 만드는 구성([ADR 013](../../decisions/013-실습-pod-격리와-백엔드-권한.md))과 같고 자원은 개발 VM 값 |

## 빌드

Docker가 있는 관리 PC에서 실행한다. 결과 tar는 `.gitignore`에 있어 커밋되지 않는다.

```bash
sh infra/lab-test-challenge/build.sh 0.1.0
# images.tar(약 136MB), lab-test-challenge-0.1.0.tar(약 271MB)
```

## 노드에 import

registry 없이 노드의 containerd에 직접 넣는다. Pod는 `imagePullPolicy: IfNotPresent`로 이 이미지를 쓴다. 운영 서버에 넣는 방법은 미정(결정 필요)이고 운영 서버 구성 때 정한다.

```bash
scp infra/lab-test-challenge/lab-test-challenge-0.1.0.tar <user>@<NODE_IP>:~/
# 노드에서
sudo ctr -n k8s.io images import --platform linux/amd64 ~/lab-test-challenge-0.1.0.tar
sudo crictl images | grep lab-test-challenge
```

## 확인

`B`는 백엔드 kubeconfig([cluster-setup.md](../cluster-setup.md) 8.3)다. exec는 백엔드 권한에 없어서 관리자 kubeconfig로 한다.

```bash
B="kubectl --kubeconfig ~/.kube/<클러스터이름>-backend.yaml"
$B create -f infra/lab-test-challenge/check.yaml
kubectl wait --for=condition=Ready pod/lab -n lab-check-challenge --timeout=180s
kubectl exec -n lab-check-challenge lab -- sh -c 'cd /app && docker compose ps'    # db, web 모두 healthy
kubectl logs -n lab-check-challenge lab | grep hackforge:                           # 단계별 시각
$B delete namespace lab-check-challenge
```

## 개발 VM 측정 결과 (2026-11-12)

개발 VM(2 vCPU, 4GB)에서 `check.yaml`과 같은 구성으로 자원만 바꿔 쟀다. 생성→Ready는 Pod 생성 시각부터 Ready condition까지다.

| Pod 자원(CPU / 메모리 / 디스크) | 생성→Ready | CPU 사용 시간 | CPU throttle | 메모리 peak | OOM |
|---|---|---|---|---|---|
| 1 / 1Gi / 4Gi | 13초 | 11.1초 | 0.9초 | 744MiB (anon 52MiB, 나머지 page cache) | 없음 |
| 1 / 512Mi / 1Gi | 14초 | | | 494MiB | 없음 |
| 500m / 512Mi / 2Gi | 21초 | 8.8초 | 6.8초 | 512MiB (한도 도달, cache 회수) | 없음 |

- CPU 1 기준 단계별 시간: container 시작 1초, dockerd 준비 4초, 이미지 load 4초, compose up 2초, Ready 판단 2초. [cluster-setup.md](../cluster-setup.md) 6단계의 image pull 방식(27.7초 중 pull 20.3초)보다 짧음
- 500m에서는 dockerd 5초, load 9초, compose up 4초로 늘어남
- 메모리 512Mi에서 한도에 닿아도 회수되는 것은 page cache라 OOM 없음(`memory.events`의 oom 0)
- 디스크: 시작 직후 kubelet 집계로 약 370MB
- 프로세스 수: 72~75개. kubelet `podPidsLimit` 4096 대비 여유 있음
- 실행 중 CPU 사용률: 서비스 두 개 합쳐 4% 안팎
- Sysbox가 `/var/lib/docker`의 emptyDir를 그대로 씀(`hostUsers: false` 포함). kubelet이 사용량을 집계하고, `sizeLimit` 1Gi를 넘기자 약 22초 뒤 `Usage of EmptyDir volume "docker" exceeds the limit` 메시지로 Pod를 eviction함
- 삭제 중인 Pod도 CPU requests를 잡고 있어서 다음 Pod가 36초 Pending이었음. `TERMINATING`을 정원에 포함하는 근거(ADR 012). 위 표의 14초는 이 Pending을 뺀 값

이 결과로 정한 개발 VM 설정값은 cpu 500m, memory 512Mi, disk 2Gi, max-concurrent 2다(ADR 012, ADR 013). 개발 VM에서 실습 Pod에 쓸 수 있는 CPU requests가 약 1150m라 500m면 세션 2개가 들어간다. 운영 값은 운영 서버에서 다시 잰다([ADR 006](../../decisions/006-개발-VM과-운영-서버.md)).
