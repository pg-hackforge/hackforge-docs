# 009. containerd 2.x에서 Sysbox를 쓰는 설정

- 상태: 채택
- 날짜: 2026-11-03

## 배경

[ADR 005](005-실습-환경-실행-기반.md)대로 containerd 2.2.1(설정 v3) 위에 Sysbox v0.7.1을 `sysbox-deploy-k8s`로 설치했다(#5). 설치 스크립트는 containerd 버전(2.0.5 이상)만 확인하고 통과했지만, Sysbox Pod는 세 번 연달아 실패했다.

1. `no runtime for "sysbox-runc"`. 설치 스크립트(`sysbox-deploy-k8s.sh`)가 런타임을 containerd 1.x 위치 `plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sysbox-runc`에 고정으로 쓴다. 설정 v3는 이 위치를 읽지 않는다.
2. `write sysctl key net.ipv4.ip_unprivileged_port_start: permission denied`. containerd 2.0부터 `enable_unprivileged_ports`와 `enable_unprivileged_icmp`의 기본값이 `true`다. containerd가 모든 Pod sandbox에 sysctl을 넣는데, Sysbox의 사용자 네임스페이스 안에서는 쓸 수 없다.
3. Pod 안 dockerd가 iptables `Permission denied`로 종료됐다. Pod에 `hostUsers: false`가 없으면 Pod 네트워크 네임스페이스가 호스트 사용자 네임스페이스 소유로 먼저 만들어진다. 그래서 컨테이너 안 root가 전체 capability를 가져도 네트워크를 바꿀 수 없다. Sysbox 문서(`install-k8s.md`)는 containerd 2.0.5 이상에서 이 줄을 요구한다.

## 선택지

1. containerd를 유지하고 세 가지를 직접 맞춘다.
2. CRI-O로 바꾼다. Sysbox가 오래 시험한 경로이고, containerd가 2.0.5보다 낮으면 설치 스크립트가 CRI-O를 설치한다.

## 결정

1번을 택한다. 클러스터마다 아래 세 가지를 지킨다.

- Sysbox 설치 뒤 containerd 설정의 `sysbox-runc` 항목을 `plugins."io.containerd.cri.v1.runtime".containerd.runtimes.sysbox-runc`로 옮기고 containerd를 재시작한다. 값(`runtime_type = "io.containerd.runc.v2"`, `BinaryName = "/usr/bin/sysbox-runc"`, `SystemdCgroup = true`)은 그대로다
- containerd 설정에서 `enable_unprivileged_ports = false`, `enable_unprivileged_icmp = false`로 둔다
- 실습 환경 Pod에는 `runtimeClassName: sysbox-runc`와 `hostUsers: false`를 함께 넣는다

## 이유

- 세 가지를 맞춘 뒤 Sysbox Pod 안에서 privileged 없이 dockerd와 `docker compose up`(nginx + PostgreSQL)이 됐다. Pod 안 root는 호스트에서 UID 594542592로 돈다.
- 2번은 런타임을 바꾸고 kubelet 설정을 다시 잡아야 한다. 1번으로 이미 동작하므로 바꿀 이유가 없다.
- `enable_unprivileged_*`를 끄는 것은 containerd 1.x와 Kubernetes의 원래 동작이다. 보안상으로는 더 좁아진다.

## 결과

- 설치 스크립트를 다시 돌려도 수정한 위치를 덮어쓰지 않는다. 스크립트는 `runtimes.sysbox-runc` 문자열이 있으면 건너뛴다. 대신 제거 스크립트(`sysbox-uninstall`)도 옛 위치만 지우므로, Sysbox를 제거할 때는 이 항목을 직접 지운다.
- root가 아닌 컨테이너가 1024 아래 포트를 열려면 `NET_BIND_SERVICE` capability가 필요하다. CoreDNS와 Calico는 영향이 없었다.
- 실습 환경 Pod 명세(#6)는 `hostUsers: false`를 전제로 한다.
- Pod 안 dockerd는 unix 소켓만 연다. `docker:dind` 이미지는 TCP 포트를 TLS 없이 열면 경고를 보여 주려고 15초를 기다린다.
- 개발 VM 실측(nginx + PostgreSQL, 이미지를 매번 Docker Hub에서 받음): Pod 생성부터 DB healthy까지 27.7초. 그중 이미지 받기가 20.3초다. 생성 시간 한도는 [ADR 006](006-개발-VM과-운영-서버.md)대로 운영 서버에서 잰다.
- Sysbox가 설치 스크립트를 고치면 첫 번째 항목은 필요 없어진다. 버전을 올릴 때 확인한다.
