# 클러스터 구성 절차

Ubuntu Server 24.04 노드 하나에 kubeadm 1.35, containerd 2.x, Calico, Sysbox를 설치하고 Sysbox Pod 안에서 Docker Compose가 도는지 확인한다. 개발 VM(#5)에서 실제로 실행한 명령이다(방화벽 절만 예외). 운영 서버도 이 순서로 구성한다.

- 결정: [ADR 005](../decisions/005-실습-환경-실행-기반.md), [ADR 006](../decisions/006-개발-VM과-운영-서버.md), [ADR 008](../decisions/008-개발-VM-실행-환경.md), [ADR 009](../decisions/009-sysbox-containerd-설정.md)
- 기준 버전 (2026-11-03): Ubuntu 24.04.5, 커널 6.8.0-147-generic, containerd 2.2.1, Kubernetes 1.35.10, Calico 3.33.0, Sysbox 0.7.1
- 구성이 바뀌면 이 문서를 같은 PR에서 고친다.

> kubeconfig, 인증서, 토큰은 커밋하지 않는다. 이 문서에도 경로만 적는다.

## 자리표시자

| 이름 | 뜻 | 개발 VM에서 쓴 값 |
|---|---|---|
| `<NODE_IP>` | API 서버와 kubelet이 쓸 노드 주소. 관리 PC에서 닿아야 한다 | 내부 스위치 주소 |
| `<POD_CIDR>` | Pod 대역. 노드·사무실 내부망과 겹치면 안 된다 | `10.244.0.0/16` |
| `<NODE_NAME>` | `kubectl get nodes`에 보이는 이름(호스트 이름) | `ubuntu` |

## 0. 전제 조건

- Ubuntu Server 24.04 LTS, **GA 커널**(6.8). HWE 커널을 고르지 않는다. Sysbox가 시험한 커널이다
- 2 CPU / 4GB 이상(kubeadm 최소 2 CPU / 1.7GB, Sysbox 권장 4 CPU / 4GB)
- **디스크는 SSD.** etcd는 동기 쓰기가 느리면 멈춘다. HDD에서 4KB 동기 쓰기 평균 95ms, 노드 전체가 38초 멈춘 기록이 있다(ADR 008)
- VM이면 하이퍼바이저가 vCPU를 제대로 돌려야 한다. Windows에서 WSL2·VBS가 켜진 PC의 VirtualBox는 안 된다(ADR 008)
- 인터넷 접속(apt, `pkgs.k8s.io`, `registry.k8s.io`, `docker.io`, `registry.nestybox.com`, GitHub raw)
- 관리 PC에서 SSH 키로 접속, 설치하는 동안 `sudo` 사용

확인:

```bash
. /etc/os-release; echo "$PRETTY_NAME"; uname -r     # Ubuntu 24.04.x LTS / 6.8.0-*-generic
nproc; free -h | head -2
stat -fc %T /sys/fs/cgroup                           # cgroup2fs
ip -4 -o addr show; ip route | head -2               # <NODE_IP>가 어느 랜카드인지 확인
```

랜카드가 둘 이상이면 kubeadm은 기본 경로의 랜카드 주소를 쓴다. 다른 주소를 써야 하면 3단계 설정 파일에 `<NODE_IP>`를 직접 적는다.

디스크가 의심되면 동기 쓰기를 잰다. 60초 동안 수천 회가 나와야 한다(SSD에서 13,061회):

```bash
end=$(( $(date +%s) + 60 )); n=0
while [ $(date +%s) -lt $end ]; do dd if=/dev/zero of=/tmp/f bs=4k count=1 oflag=dsync 2>/dev/null; n=$((n+1)); done
echo "$n syncs/60s"; rm -f /tmp/f
```

## 1. OS 준비

```bash
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
[ -f /var/run/reboot-required ] && sudo reboot

# swap을 끈다. kubelet은 swap이 켜져 있으면 시작하지 않는다
sudo swapoff -a
sudo sed -i '/^\/swap.img/s/^/#/' /etc/fstab     # swap 줄 이름이 다르면 /etc/fstab을 직접 본다
sudo rm -f /swap.img

# 커널 모듈
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf
sudo modprobe overlay && sudo modprobe br_netfilter

# sysctl
printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n' | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system
```

확인 (재부팅 후에도 같아야 한다):

```bash
swapon --show                                        # 출력 없음
lsmod | grep -E '^(overlay|br_netfilter)'            # 두 줄
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward   # 모두 1
```

## 2. containerd

Ubuntu 24.04 `noble-updates`의 containerd가 2.x다(2026-11 기준 2.2.1). Sysbox는 2.0.5 이상을 요구한다.

```bash
sudo apt-get install -y containerd
containerd --version                                 # 2.0.5 이상

sudo mkdir -p /etc/containerd
[ -f /etc/containerd/config.toml ] && echo "기존 설정이 있다. 덮어쓰기 전에 백업한다"
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null     # 설정 v3

# kubelet 기본 cgroup 드라이버(systemd)와 맞춘다
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# containerd 2.x 기본값 true를 끈다. 켜 두면 Sysbox Pod sandbox가 sysctl 권한 오류로 안 뜬다(ADR 009)
sudo sed -i 's/enable_unprivileged_ports = true/enable_unprivileged_ports = false/; s/enable_unprivileged_icmp = true/enable_unprivileged_icmp = false/' /etc/containerd/config.toml

sudo systemctl restart containerd && sudo systemctl enable containerd
```

확인:

```bash
head -1 /etc/containerd/config.toml                  # version = 3
grep -n -E 'SystemdCgroup|enable_unprivileged|sandbox = ' /etc/containerd/config.toml
#   runc options 아래 SystemdCgroup = true
#   enable_unprivileged_icmp = false, enable_unprivileged_ports = false
#   sandbox = 'registry.k8s.io/pause:3.10.1'  (3단계의 kubeadm 요구 버전과 같아야 한다)
systemctl is-active containerd                       # active
```

## 3. kubeadm 1.35와 클러스터 생성

```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm | head -3                  # 1.35 최신 패치를 고른다
sudo apt-get install -y kubelet=1.35.10-1.1 kubeadm=1.35.10-1.1 kubectl=1.35.10-1.1
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

설정 파일 `~/kubeadm-config.yaml`:

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: <NODE_IP>
nodeRegistration:
  kubeletExtraArgs:
    - name: node-ip
      value: <NODE_IP>
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.10
networking:
  podSubnet: <POD_CIDR>
```

```bash
kubeadm config images list --config ~/kubeadm-config.yaml | grep pause    # 2단계 sandbox 값과 같은지
sudo kubeadm init --config ~/kubeadm-config.yaml | tee ~/kubeadm-init.log
chmod 600 ~/kubeadm-init.log        # 마지막의 kubeadm join 줄에 토큰이 있다. 공유하지 않는다

mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown "$(id -u):$(id -g)" ~/.kube/config && chmod 600 ~/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/control-plane-          # 단일 노드라 일반 Pod도 올린다
```

확인: SSD 노드에서 `kubeadm init`은 10초 안쪽에 끝난다. 수 분이 걸리거나 `wait-control-plane`에서 실패하면 디스크와 vCPU부터 의심한다(아래 "알려진 함정").

```bash
kubectl get nodes -o wide                            # INTERNAL-IP가 <NODE_IP>. CNI 전이라 NotReady가 정상
kubectl get pods -n kube-system                      # etcd·apiserver·controller-manager·scheduler·kube-proxy Running, coredns Pending
```

## 4. Calico 3.33

Calico 3.33은 Kubernetes 1.35~1.37에서 시험됐다.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=120s
```

기본 `custom-resources.yaml`에서 Pod 대역을 바꾸고 Goldmane·Whisker(흐름 로그 수집기와 UI)는 뺀다. 메모리를 아끼고, NetworkPolicy는 이 둘 없이 동작한다.

```bash
kubectl create -f - <<'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: <POD_CIDR>
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
```

확인:

```bash
kubectl wait --for=condition=Ready node/<NODE_NAME> --timeout=300s
kubectl get tigerastatus                             # apiserver·calico·ippools·tiers 모두 AVAILABLE True (tiers는 잠깐 늦을 수 있다)
kubectl get pods -A -o wide                          # coredns가 <POD_CIDR> 대역 IP로 Running
kubectl run dnstest --image=busybox:1.37 --restart=Never --rm -i --quiet --command -- nslookup kubernetes.default.svc.cluster.local 10.96.0.10
#   Address: 10.96.0.1
kubectl run nettest --image=busybox:1.37 --restart=Never --rm -i --quiet --command -- wget -q -T 5 -O /dev/null https://registry.k8s.io/ && echo "egress ok"
```

## 5. Sysbox 0.7.1

`v0.7.1` 태그의 manifest는 아직 v0.7.0 설치 이미지를 가리킨다. v0.7.1 이미지로 바꾼 커밋 `f7c43922753b`에 고정한다. 설치 Pod는 privileged로 노드에 Sysbox를 설치하고 containerd와 kubelet을 재시작한다. 잠깐 노드가 NotReady가 되는 것은 정상이다.

```bash
kubectl label nodes <NODE_NAME> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/f7c43922753b/sysbox-k8s-manifests/sysbox-install.yaml
kubectl wait node/<NODE_NAME> --for=jsonpath='{.metadata.labels.sysbox-runtime}'=running --timeout=600s    # 개발 VM에서 74초
```

**설치 직후 containerd 설정을 고친다(ADR 009).** 설치 스크립트가 `sysbox-runc`를 containerd 1.x 위치에 써서, 설정 v3에서는 인식되지 않는다.

```bash
sudo containerd config dump | grep -E 'runtimes\.(runc|sysbox-runc)\]'    # 고치기 전: runc 한 줄뿐
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.sysbox-v2key
sudo sed -i 's/plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.sysbox-runc/plugins."io.containerd.cri.v1.runtime".containerd.runtimes.sysbox-runc/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo containerd config dump | grep -E 'runtimes\.(runc|sysbox-runc)\]'    # 고친 뒤: 두 줄
```

남는 빈 `grpc.v1.cri.containerd` 표 때문에 `Ignoring unknown key in TOML` 경고가 나오지만 무시해도 된다. 설치 스크립트가 다시 돌아도 이 수정을 덮어쓰지 않는다.

확인:

```bash
systemctl is-active sysbox sysbox-mgr sysbox-fs      # active ×3
sudo journalctl -u sysbox-mgr -b | grep -E 'ID-mapped mounts supported|Ready'    # yes / Ready
kubectl get runtimeclass                             # sysbox-runc
kubectl get node <NODE_NAME> -L sysbox-runtime        # running
```

## 6. Sysbox Pod와 Compose 확인

실습 환경 Pod는 **`runtimeClassName: sysbox-runc`와 `hostUsers: false`를 함께** 쓴다. `hostUsers: false`가 없으면 Pod 안 dockerd가 iptables `Permission denied`로 죽는다(ADR 009). dockerd는 unix 소켓만 연다. TCP를 열면 `docker:dind`가 경고 때문에 15초를 기다린다.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sysbox-check
spec:
  runtimeClassName: sysbox-runc
  hostUsers: false
  containers:
    - name: dind
      image: docker:27-dind
      args: ["--host=unix:///var/run/docker.sock"]
EOF
kubectl wait pod/sysbox-check --for=condition=Ready --timeout=180s
until kubectl exec sysbox-check -- docker info >/dev/null 2>&1; do sleep 1; done

kubectl exec sysbox-check -- cat /proc/self/uid_map          # 0 <큰 수> 65536  (Pod 안 root가 호스트에선 일반 UID)
kubectl exec sysbox-check -- docker run --rm hello-world | grep "Hello from Docker"
```

Compose(nginx + PostgreSQL):

```bash
kubectl exec -i sysbox-check -- sh -c 'mkdir -p /lab && cat > /lab/compose.yaml' <<'EOF'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: lab
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 1s
      retries: 60
  web:
    image: nginx:1.27-alpine
    ports: ["8080:80"]
    depends_on:
      db:
        condition: service_healthy
EOF
time kubectl exec sysbox-check -- sh -c 'cd /lab && docker compose up -d --wait'
kubectl exec sysbox-check -- wget -q -S -O /dev/null http://localhost:8080 2>&1 | grep 'HTTP/'      # 200
kubectl exec sysbox-check -- sh -c 'cd /lab && docker compose exec -T db psql -U postgres -tAc "select 1"'   # 1
kubectl delete pod sysbox-check
```

개발 VM에서는 Pod 생성부터 DB healthy까지 27.7초가 걸렸고, 그중 이미지 받기가 20.3초였다. 운영 서버에서는 Pod 생성부터 끝까지 단계별 시간을 재서 환경 생성 시간 한도(product.md 미정)의 근거로 남긴다.

## 7. 원격 kubectl과 정리

관리 PC로 kubeconfig를 복사한다. 내용을 화면이나 로그에 찍지 않는다.

```bash
# 관리 PC에서
ssh <user>@<NODE_IP> 'cat ~/.kube/config' > ~/.kube/<클러스터이름>.yaml
kubectl --kubeconfig ~/.kube/<클러스터이름>.yaml get nodes
```

- kubectl은 서버와 마이너 버전 ±1까지 지원된다(1.35 서버에 1.34~1.36)
- 관리 PC에서 `<NODE_IP>:6443`에 닿아야 한다
- 설치 동안 쓴 임시 `sudo` NOPASSWD 설정이 있으면 지운다

## 방화벽

개발 VM에서는 방화벽을 켜지 않아 이 절은 시험하지 않았다. 운영 서버에서 확인하고 고친다. Ubuntu Server는 기본으로 `ufw`가 꺼져 있다. 켤 때 단일 노드에서 밖에서 들어와야 하는 것은 SSH(22)와 API 서버(6443, 관리 PC만)다. 노드를 늘리면 노드끼리 10250(kubelet), 4789/udp(Calico VXLAN), 5473(Calico Typha)도 연다. 실습 대상 앱과 IDE를 밖에 노출하는 방식은 #8·#10에서 정한다.

## 알려진 함정

| 증상 | 원인 | 조치 |
|---|---|---|
| `kubeadm init`이 `wait-control-plane`에서 수 분 뒤 실패. 커널 로그에 `soft lockup - CPU#N stuck for NNNs` | VM의 vCPU가 멈춘다(Windows 하이퍼바이저 위의 VirtualBox NEM 모드) | 하이퍼바이저를 바꾼다(ADR 008) |
| 부하가 걸리면 노드 전체가 수십 초 멈춤. soft lockup은 없음 | 디스크 동기 쓰기 지연(HDD) | SSD로 옮긴다. 0단계 측정으로 확인 |
| Sysbox Pod: `no runtime for "sysbox-runc"` | 설치 스크립트가 런타임을 containerd 1.x 위치에 씀 | 5단계 수정 |
| Sysbox Pod: `write sysctl key net.ipv4.ip_unprivileged_port_start: permission denied` | containerd 2.x 기본값 `enable_unprivileged_* = true` | 2단계 설정 |
| Pod 안 dockerd: `iptables ... Permission denied (you must be root)` | Pod에 `hostUsers: false` 없음 | 6단계 Pod 명세 |
| dockerd가 15초 넘게 늦게 뜸 | `docker:dind`가 TCP 2375를 TLS 없이 열어 경고 대기 | `--host=unix:///var/run/docker.sock`만 쓴다 |
| Calico 설치 후 Pod 통신·DNS가 이상함 | Pod 대역이 노드 내부망과 겹침(기본 `192.168.0.0/16`) | `<POD_CIDR>`를 겹치지 않게 다시 잡는다 |

## Sysbox 제거

`sysbox-uninstall.yaml`의 제거 스크립트는 containerd 1.x 위치의 `sysbox-runc`만 지운다. 5단계에서 옮긴 `plugins."io.containerd.cri.v1.runtime".containerd.runtimes.sysbox-runc` 항목(과 `.options`)은 직접 지우고 containerd를 재시작한다.
