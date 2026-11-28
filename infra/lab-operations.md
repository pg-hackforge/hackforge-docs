# 실습 환경 운영 runbook

실습 세션을 관리자가 직접 확인하고 정리하는 절차와, 실습 Pod 격리를 확인하는 절차다. 보안 확인 결과는 2026-11-13 개발 VM에서 실제 백엔드로 세션을 만들어 확인한 값이다.

- 결정: [ADR 012](../decisions/012-실습-환경-수명-주기.md)(수명 주기, reconciler), [ADR 013](../decisions/013-실습-pod-격리와-백엔드-권한.md)(격리와 백엔드 권한)
- 클러스터 정책 적용: [cluster-setup.md](cluster-setup.md) 8단계
- 기준: hackforge-be #31(실습 idle 종료와 활동 기록 API)까지. Pod spec이나 reconciler 동작이 바뀌면 같은 PR에서 이 문서도 고친다.
- 문제 등록과 첫 문제 측정(4, 5절): [ADR 014](../decisions/014-challenge-형식과-등록.md), 2026-11-16
- 문제 2·3 측정(7절): [specs/more-challenges](../specs/more-challenges/tasks.md) 작업 8, 2026-11-28

## placeholder

| 이름 | 뜻 | 개발 환경 값 |
|---|---|---|
| `<PSQL>` | 플랫폼 DB에 psql로 접속하는 명령 | hackforge-be 폴더에서 `docker compose exec postgres psql -U hackforge` |
| `<BASE_URL>` | 백엔드 주소 | `http://127.0.0.1:8080` |
| `K` | 관리자 kubeconfig로 실행하는 kubectl | `kubectl --kubeconfig ~/.kube/<클러스터이름>.yaml` |
| `<NODE_IP>` | 노드 IP | 개발 VM IP |
| `<ID>` | 세션 id. namespace는 `lab-<ID>`, Pod 이름은 `lab` | |

백엔드 권한에는 `pods/exec`가 없으므로 Pod 안에 들어가는 확인은 관리자 kubeconfig로 한다.

## 1. 세션 상태 보기

```bash
# 진행 중 세션
<PSQL> -c "select id, user_id, status, start_attempts, status_changed_at, last_activity_at from lab_sessions where status not in ('DELETED', 'FAILED') order by id"
# 클러스터에 있는 실습 namespace. 진행 중 세션과 같아야 한다(종료 중인 것은 삭제가 끝날 때까지 보임)
$K get namespaces -l hackforge/lab=true
$K get pod lab -n lab-<ID> -o wide
$K get events -n lab-<ID> --sort-by=.lastTimestamp
```

상태 전이는 백엔드 로그에 `실습 세션 <ID> (사용자 <USER_ID>): <이전> -> <다음>, <사유>` 형식으로 남는다. orphan namespace 삭제는 `실습 namespace lab-<ID>: 진행 중 세션이 없어서 삭제`로 남는다.

## 2. 문제가 생겼을 때

| 증상 | 확인 | 조치 |
|---|---|---|
| `CREATING`, `INITIALIZING`에 오래 머묾 | `get events`, `get pod lab -o yaml`의 `status` | 손대지 않아도 `start-timeout`(5m) 뒤 재시도 1회, 다시 실패하면 `FAILED`로 끝남 |
| `TERMINATING`에 오래 머묾 | `$K get namespace lab-<ID> -o yaml`의 `status.conditions` | namespace 삭제가 끝나야 `DELETED`가 됨. 삭제를 막는 원인(finalizer 등)을 conditions에서 확인 |
| `READY`가 갑자기 `DELETED`(`POD_LOST`) | `get events -n lab-<ID>`는 namespace가 지워지기 전에만 볼 수 있음. 백엔드 로그의 `Pod FAILED` | 메모리 초과(`OOMKilled`)나 디스크 초과(`Evicted`)가 흔한 원인. 3.3, 3.4 참고 |
| DB에 없는 `lab-` namespace가 남음 | `get namespaces -l hackforge/lab=true` | 백엔드가 시작할 때와 5분마다 자동 삭제. 바로 지우려면 `$K delete namespace lab-<ID>` |
| 학습자 대신 세션을 끝내야 함 | 1절 쿼리 | 아래 SQL. reconciler가 다음 주기(3초)에 namespace를 지우고 `DELETED`로 끝냄 |

```sql
-- 진행 중일 때만 바꾼다. version을 올려야 그 전에 세션을 읽은 reconciler가 덮어쓰지 않는다
update lab_sessions
set status = 'TERMINATING', end_reason = 'USER', status_changed_at = now(), version = version + 1
where id = <ID> and status in ('CREATING', 'INITIALIZING', 'READY');
```

## 3. 보안 확인

백엔드를 클러스터에 연결해 띄우고(hackforge-be `CLAUDE.md`의 `HACKFORGE_LAB_KUBECONFIG`), 승인된 학습자 두 명으로 실습을 시작해 세션 두 개를 `READY`로 만든다. 아래에서 `A`, `B`는 두 세션의 id다. 3.3과 3.4는 Pod를 죽이므로 3.1, 3.2를 먼저 하고, 3.4는 새 세션으로 한다.

### 3.1 네트워크

`B` Pod에 listener를 띄우고, 대조군으로 `default` namespace에 같은 확인용 Pod를 둔다.

```bash
$K exec -n lab-B lab -- sh -c 'nohup sh -c "while true; do nc -l -p 9999 </dev/null; done" >/dev/null 2>&1 & sleep 1; nc -z -w 3 127.0.0.1 9999 && echo self-open'
$K run probe -n default --image=busybox:1.37 --restart=Never --command -- sleep 900
B_IP=$($K get pod lab -n lab-B -o jsonpath='{.status.podIP}')
T="1.1.1.1:80 10.96.0.1:443 10.96.0.10:53 <NODE_IP>:6443 <NODE_IP>:10250 <NODE_IP>:22 $B_IP:9999"
probe() { for t in $T; do echo "$t $("$@" sh -c "nc -z -w 3 ${t%:*} ${t#*:} && echo open || echo blocked" 2>&1 | tail -1)"; done; }
probe $K exec -n default probe --                         # 대조군
probe $K exec -n lab-A lab --                             # 실습 Pod
probe $K exec -n lab-A lab -- docker exec app-web-1       # 실습 Pod 안의 compose container
$K exec -n lab-A lab -- sh -c 'timeout 5 nslookup example.com >/dev/null 2>&1 && echo resolved || echo failed'
$K delete pod probe -n default
```

| 대상 | 대조군(`default`) | 실습 Pod | Pod 안 compose container |
|---|---|---|---|
| 인터넷 `1.1.1.1:80` | open | blocked | blocked |
| API server `10.96.0.1:443` | open | blocked | blocked |
| DNS `10.96.0.10:53`, `nslookup example.com` | open, resolved | blocked, failed | blocked |
| API server `<NODE_IP>:6443` | open | blocked | blocked |
| kubelet `<NODE_IP>:10250` | open | blocked | blocked |
| 노드 SSH `<NODE_IP>:22` | open | blocked | blocked |
| 다른 세션 Pod `B_IP:9999` | blocked | blocked | blocked |

`B` 안에서 자기 자신(`127.0.0.1:9999`)은 open이라 listener는 떠 있었다. 대조군에서도 `B`로 못 들어가므로 실습 Pod로 들어오는 연결도 막혀 있다. Pod 안 compose container 사이 통신(`web` → `db` IP)은 된다.

### 3.2 service account token과 user namespace

```bash
$K exec -n lab-A lab -- ls /var/run/secrets/kubernetes.io   # 없어야 함
$K exec -n lab-A lab -- cat /proc/self/uid_map              # 0 0 4294967295가 아니어야 함
```

결과: token 폴더 없음. `uid_map`은 `0 3048603648 65536`이라 Pod 안 root가 노드에서는 일반 사용자다.

### 3.3 fork bomb

이웃 세션, 백엔드, 노드가 영향을 받지 않는지 본다. 노드의 Pod cgroup은 SSH로 일반 권한으로 읽는다.

```bash
timeout 25 $K exec -n lab-A lab -- sh -c 'f(){ f|f& }; f; sleep 20' &
# 10초쯤 뒤
UID_A=$($K get pod lab -n lab-A -o jsonpath='{.metadata.uid}')
ssh <노드> "cat /sys/fs/cgroup/kubepods.slice/kubepods-pod${UID_A//-/_}.slice/pids.max; uptime"
$K exec -n lab-B lab -- echo ok
curl -s -o /dev/null -w '%{http_code}\n' -b <학습자 B cookie> <BASE_URL>/api/labs/B
$K get pod lab -n lab-A -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}'
```

결과:

- Pod cgroup의 `pids.max`는 4096(kubelet `podPidsLimit`)
- 약 10초 만에 Pod의 container가 `OOMKilled`(메모리 limit 512Mi)로 끝났다. 프로세스 수가 4096에 닿기 전에 메모리가 먼저 찼다(`pids.events`의 `max 0`). `sleep` 프로세스만 계속 띄워도 같았다
- reconciler가 Pod `Failed`를 보고 `POD_LOST`로 종료했고, namespace 삭제 후 `DELETED`가 됐다
- 그동안 이웃 세션 exec, 백엔드 응답(200, 약 10ms), `kubectl get nodes`(Ready)가 모두 정상이었다. 노드 load average는 511까지 올랐다가 몇 분 안에 내려갔다. CPU limit(500m)이 Pod의 CPU 사용을 제한해서 load average가 높아도 노드는 응답했다
- 메모리 512Mi에서는 메모리 limit이 먼저 막고, `podPidsLimit`은 프로세스가 메모리를 적게 쓰는 경우를 위한 두 번째 상한이다

### 3.4 디스크

```bash
$K exec -n lab-A lab -- sh -c 'dd if=/dev/zero of=/var/lib/docker/fill bs=1M count=2500'   # emptyDir
$K exec -n lab-A lab -- sh -c 'dd if=/dev/zero of=/root/fill bs=1M count=2500'             # container 쓰기 계층
$K get pod lab -n lab-A -o jsonpath='{.status.reason} {.status.message}'
```

| 쓴 곳 | 결과 | 걸린 시간 |
|---|---|---|
| `/var/lib/docker`(emptyDir `sizeLimit: 2Gi`) | `Evicted`: `Usage of EmptyDir volume "docker" exceeds the limit "2Gi".` | dd 종료 후 약 15초 |
| `/root`(container 쓰기 계층) | `Evicted`: `Pod ephemeral local storage usage exceeds the total limit of containers 2Gi.` | 약 15초 |

두 경우 모두 reconciler가 `POD_LOST`로 종료하고 namespace를 지웠다. 다른 세션은 `READY`로 남았고, 노드 디스크 사용량은 확인 전과 같았다(Pod와 함께 지워짐).

## 4. 문제 등록

형식과 스크립트는 [ADR 014](../decisions/014-challenge-형식과-등록.md)와 각 문제 저장소 README에 있다. 순서는 빌드, 노드 import, 등록이다. import 전에 등록하면 그 사이 시작한 세션이 이미지를 찾지 못해 `FAILED`가 된다.

진행 중 세션이 있는 문제는 다시 등록하지 않는다. 세션은 이미지만 시작할 때 고정하고 검증 스크립트, 힌트, 해답은 검증할 때마다 `challenges`에서 읽으므로, 그 세션이 옛 이미지와 새 스크립트로 검증받는다([ADR 031](../decisions/031-문제-상태와-버전.md), v1.2 버전 분리로 해결). 등록 전에 1절의 진행 중 세션에서 그 문제를 확인한다.

```bash
# 관리 PC, 문제 저장소에서
sh build.sh <TAG>                    # challenge-<SLUG>-<TAG>.tar
scp challenge-<SLUG>-<TAG>.tar <user>@<NODE_IP>:~/
# 노드에서. 개발 VM에는 crictl이 없어 ctr로 확인한다
sudo ctr -n k8s.io images import --platform linux/amd64 ~/challenge-<SLUG>-<TAG>.tar
sudo ctr -n k8s.io images ls -q | grep challenge-<SLUG>
# 관리 PC, 문제 저장소에서. register.sh는 stdin을 넘기므로 <PSQL>에 -T(docker compose exec)나 -i(docker exec, kubectl exec)가 필요하다
PSQL="docker exec -i hackforge-be-postgres-1 psql -U hackforge" sh register.sh <TAG>
```

## 5. 첫 문제(`sqli-login`) 측정 (2026-11-16)

개발 VM(2 vCPU, 4GB)에서 백엔드 API로 `sqli-login` 1.0.0 세션을 시작해 쟀다. Pod 자원은 개발 VM 값(CPU 500m, 메모리 512Mi, 디스크 2Gi)이다.

| 항목 | 값 |
|---|---|
| Pod 생성 → Ready | 69초 (API 요청부터 `READY` 응답까지 71초) |
| 단계별 시간 | container 시작 2초, dockerd 준비 4초, 이미지 load 44초, compose up 15초(MySQL 초기화와 healthy 대기 포함), Ready 판단 4초 |
| CPU | 사용 30.1초 중 throttle 27.7초. 이미지 load가 CPU 500m에 묶여 가장 오래 걸림 |
| 메모리 | peak 512MiB(limit 도달), 그중 anon 241MiB, page cache 199MiB. OOM 0. inner container는 `db` 202MiB, `web` 47MiB |
| 디스크(kubelet 집계) | 1555MiB / 2Gi. inner docker 이미지 1.32GB(`mysql` 810MB, `web`과 base가 공유하는 510MB), MySQL volume 219MB |

검증 스크립트는 백엔드가 쓸 방식대로 `$K exec -i -n lab-<ID> lab -- sh -c 'cd /app && timeout 60 sh' < meta/<스크립트>`로 실행했다.

| 순서 | 스크립트 | exit | 마지막 줄 | 걸린 시간 |
|---|---|---|---|---|
| 1 | `attack-check.sh` | 1 | admin으로 로그인한 기록 없음 | 1초 안 |
| 2 | `functional-test.sh` | 0 | 정상 기능 3개 모두 동작 | 1초 안 |
| 3 | `exploit.sh` | 0 | payload 5개 중 5개가 아직 통함 | 1초 안 |
| 4 | `attack-check.sh` | 0 | admin으로 로그인함 (5회) | 1초 |
| 5 | 해답대로 `index.php` 수정, `docker compose build web`, `up -d` | 0 | | 4초, Ready까지 7초 |
| 6 | `exploit.sh` | 1 | payload 5개 모두 막힘 | 1초 안 |
| 7 | `functional-test.sh` | 0 | 정상 기능 3개 모두 동작 | 1초 안 |

- 메모리 512Mi 안에서 동작한다. limit에 닿는 것은 page cache라 회수되고, 재빌드 뒤에도 OOM은 없었다(ADR 014의 실측 항목)
- 디스크는 시작 직후부터 2Gi의 약 76%를 쓴다. 재빌드는 base 위 `COPY` 계층만 늘어서 거의 늘지 않는다. 이미지가 더 큰 문제를 추가하면 여유가 부족할 수 있다
- 디스크는 2Gi를 유지하고, 문제 이미지 묶음(`images.tar`)은 첫 문제 수준인 450MB 이하로 둔다(2026-11-26 사람이 결정)
- kubelet 디스크 집계는 바로 갱신되지 않는다. Ready 직후 510MiB로 보였다가 다음 갱신에 1555MiB가 됐다
- `kubectl exec`가 0이 아닌 exit code로 끝나면 kubectl이 stderr에 `command terminated with exit code 1`을 덧붙인다. 결과 메시지는 stdout의 마지막 줄만 읽어야 한다(#9, #11)

## 6. 공격 대상 port-forward와 터미널 exec 확인 (2026-11-20)

ADR 022(공격 대상과 웹 터미널 연결)의 확인 작업이다. 개발 VM(2 vCPU, 4GB)에서 백엔드 API로 `sqli-login` 1.0.0 세션을 시작하고(`READY`까지 74초), 관리자 kubeconfig의 `kubectl`로 확인했다. 백엔드 권한(`hackforge-lab-connect`)은 아직 없어서 쓰지 않았다. 부하는 개발 PC에서 k6(v1.7.1)로 port-forward한 주소에 `GET /`를 보냈다.

| 항목 | 결과 |
|---|---|
| exec | `sh -c` 실행 성공. 작업 폴더 `/app`, uid 0, `sh`는 busybox. `docker compose ps`로 `db`, `web` 모두 running, healthy |
| exec TTY | `kubectl exec -t`는 PC 쪽 입력이 터미널이 아니면 TTY를 만들지 않아 확인하지 못함. 백엔드가 client-java로 TTY를 요청하는 것은 작업 5와 8에서 확인 |
| port-forward | `kubectl port-forward pod/lab 18080:8080`으로 Pod 안 `127.0.0.1:8080`의 로그인 페이지가 열림(첫 요청 200, 4ms). NetworkPolicy와 GlobalNetworkPolicy는 그대로 |
| 부하 1000개(동시 10) | 초당 609개, 실패 0. 응답 중앙값 1.5ms, p95 15.5ms, p99 181ms, 최대 1.17초(시작할 때 연결을 여는 몇 개) |
| 부하 5000개(동시 10) | 초당 1669개, 실패 0. 응답 중앙값 3.2ms, p95 32ms, p99 40ms, 최대 51ms |
| API server CPU | 부하 중 평균 0.20 core, 부하 없을 때 0.03 core(`process_cpu_seconds_total`) |
| kubelet CPU | 부하 중 평균 약 0.04 core. kubelet 통계는 늦게 갱신돼서 부하 뒤 20초를 포함해 나눈 값이라 실제보다 낮게 나옴 |

- port-forward와 exec 모두 Sysbox Pod(`hostUsers: false`)에서 동작한다. ADR 022의 경로를 그대로 쓴다
- 초당 1600개를 넘는 요청도 실패 없이 지나가고 API server가 0.2 core 정도 더 쓴다. sqlmap 한 명은 보통 이보다 훨씬 적은 요청을 보내므로 30세션 기준에서 여유가 있다. ADR 022의 이전 기준(동시 100세션, API server가 실습 생성과 종료를 늦춤)은 운영 서버에서 다시 잰다
- Pod 안에서 직접 요청하는 기준값은 busybox `date`가 나노초(`%N`)를 지원하지 않아 재지 못했다. 위 응답 시간에는 공격 대상 앱(PHP)의 처리 시간이 포함돼 있다
- Git Bash에서 `kubectl`에 `/metrics`, `/app` 같은 인자를 넘길 때는 `MSYS_NO_PATHCONV=1`을 kubectl에만 붙인다. 전체에 켜면 `curl`의 cookie 파일 경로가 바뀌지 않아 로그인이 실패한다

## 7. 문제 2·3(`idor-memo`, `cmdi-ping`) 측정 (2026-11-28)

개발 VM(2 vCPU, 4GB)에서 두 문제를 `main`에서 `build.sh 1.0.0`으로 빌드해 4절 순서대로 import하고 `register.sh 1.0.0`으로 등록했다. 두 문제 모두 예정에서 공개로 바뀌고 `published_at`이 등록 시각으로 채워졌다. Pod 자원은 5절과 같다(CPU 500m, 메모리 512Mi, 디스크 2Gi).

5절과 달리 검증과 수정을 모두 학습자와 같은 백엔드 API로 했다. 승인된 학습자 계정으로 세션을 시작하고 공격 검증, 방어 검증, 파일 저장(`PUT /api/labs/{id}/files/content`), 재배포 API를 차례로 불렀다. 공격만 학습자 터미널 대신 관리자 kubeconfig의 `kubectl exec`로 Pod 안에서 해답(`solution.md`)의 공격 명령을 실행했다. `idor-memo`는 같은 순서로 두 번(세션 77, 79), `cmdi-ping`은 한 번(세션 78) 쟀다.

| 항목 | `idor-memo` | `cmdi-ping` |
|---|---|---|
| `images.tar` / Challenge 이미지 tar | 61MiB / 191MiB | 21MiB / 152MiB |
| API 요청 → `READY` | 17초, 18초 | 18초 |
| 준비 단계가 처음 보인 시각 | `CONTAINER` 2초, `LOADING` 8초, `STARTING` 14초 | `CONTAINER` 1초, `LOADING` 9초, `STARTING` 12초 |
| Pod 로그 단계 | dockerd 준비 4초, 이미지 load 6초, compose up 1초 | dockerd 준비 6초, 이미지 load 3초, compose up 1초 |
| CPU(`READY`까지) | 사용 5.3초 중 throttle 3.9초 | 사용 5.7초 중 throttle 3.7초 |
| 메모리 peak | 179MiB, 309MiB. anon 52~72MiB. OOM 0 | 217MiB. anon 82~90MiB. OOM 0 |
| inner container 메모리 | `web` 20~79MiB | `web` 48~51MiB |
| 디스크(kubelet 집계, 60초 동안 최대) | 182MiB / 2Gi. inner docker 이미지 176MB | 68MiB / 2Gi. inner docker 이미지 60MB |
| 종료 요청 → `DELETED` | 48초 | 46초 |

| 순서 | 요청 | `idor-memo` | `cmdi-ping` |
|---|---|---|---|
| 1 | 공격 검증(공격 전) | `FAIL` 다른 회원의 메모를 읽은 기록 없음, 0.3~0.5초 | `FAIL` 관리자 토큰이 드러난 기록 없음, 0.3초 |
| 2 | Pod 안에서 해답의 공격 명령 | `admin`의 1번 메모 응답 | 진단 결과에 토큰 `HF-...` |
| 3 | 공격 검증 | `PASS` 다른 회원의 메모를 읽음 (1회). 단계 `DEFENSE` | `PASS` 관리자 토큰이 진단 결과에 드러남 (1건). 단계 `DEFENSE` |
| 4 | 방어 검증(원본 그대로) | `FAIL` 요청 8개 중 8개가 아직 통함, 정상 기능 통과, 4초 | `FAIL` payload 4개 중 4개가 토큰을 드러냄, 정상 기능 통과, 11초 |
| 5 | 해답대로 파일 저장, 재배포 | `web/src/memos.js`, 재배포 `SUCCESS` 14초 | `web/src/app.py`, 재배포 `SUCCESS` 4.5초 |
| 6 | 방어 검증 | `PASS` 요청 8개 모두 막힘, 정상 기능 통과, 4초. `completedAt` 기록 | `PASS` payload 4개 모두 막힘, 정상 기능 통과, 1.4초. `completedAt` 기록 |

- 두 문제 모두 메모리 512Mi, 디스크 2Gi, `images.tar` 450MB 기준 안에서 동작한다. 메모리 peak의 대부분은 회수되는 page cache이고 anon은 90MiB를 넘지 않았다. 재배포 뒤에도 OOM은 없었다
- 공개 이미지가 작아서(`sqli-login`은 MySQL 이미지 포함 1.32GB) `READY`까지 `sqli-login`(71초)의 4분의 1 정도다
- `cmdi-ping` 방어 검증이 원본에서 11초 걸린 것은 payload마다 ping을 실제로 보내기 때문이다. 60초 제한 안이다
- `idor-memo` 해답의 공격 명령은 그대로 실행하면 실패했다. busybox `wget`이 로그인 뒤 redirect를 따라가며 로그인 요청을 되풀이해서 `Set-Cookie` 줄이 8개 나오고, 그 8줄이 `Cookie` header에 들어갔다. `exploit.sh`처럼 첫 줄만 쓰게 고쳤다(hackforge-challenge-idor-memo #2). 해답은 등록할 때 DB에 들어가므로 머지 뒤 다시 등록한다

## known issues

| 증상 | 원인 | 조치 |
|---|---|---|
| Pod 안 compose container가 서비스 이름(`db`)으로 접속하지 못함. IP로는 됨 | inner docker가 Pod의 `/etc/resolv.conf`(`search lab-<ID>.svc.cluster.local ...`, `ndots:5`)를 container에 물려줌. `db`를 `db.lab-<ID>.svc.cluster.local`부터 찾고, 그 질의를 클러스터 DNS로 보내다 GlobalNetworkPolicy에 막혀 timeout | Pod spec에 `dnsPolicy: None`, `dnsConfig: {nameservers: [127.0.0.1]}`(ADR 013, hackforge-be에서 반영). `check.yaml`로 확인: `web`에서 `db`로 이름 접속 성공, 인터넷은 계속 막힘 |
