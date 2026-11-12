# 실습 환경 운영 runbook

실습 세션을 관리자가 직접 확인하고 정리하는 절차와, 실습 Pod 격리를 확인하는 절차다. 보안 확인 결과는 2026-11-13 개발 VM에서 실제 백엔드로 세션을 만들어 확인한 값이다.

- 결정: [ADR 012](../decisions/012-실습-환경-수명-주기.md)(수명 주기, reconciler), [ADR 013](../decisions/013-실습-pod-격리와-백엔드-권한.md)(격리와 백엔드 권한)
- 클러스터 정책 적용: [cluster-setup.md](cluster-setup.md) 8단계
- 기준: hackforge-be #31(실습 idle 종료와 활동 기록 API)까지. Pod spec이나 reconciler 동작이 바뀌면 같은 PR에서 이 문서도 고친다.

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

## known issues

| 증상 | 원인 | 조치 |
|---|---|---|
| Pod 안 compose container가 서비스 이름(`db`)으로 접속하지 못함. IP로는 됨 | inner docker가 Pod의 `/etc/resolv.conf`(`search lab-<ID>.svc.cluster.local ...`, `ndots:5`)를 container에 물려줌. `db`를 `db.lab-<ID>.svc.cluster.local`부터 찾고, 그 질의를 클러스터 DNS로 보내다 GlobalNetworkPolicy에 막혀 timeout. container에서 `search`와 `options` 줄을 지우면 바로 됨 | 미정(결정 필요): Pod spec에 `dnsPolicy: None`과 `dnsConfig`(search 없음)를 넣는 수정. 서비스 이름을 쓰는 문제를 올리기 전에 해야 함 |
