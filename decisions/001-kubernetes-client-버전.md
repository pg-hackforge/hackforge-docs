# 001. Kubernetes 클라이언트: client-java 27.0.1

- 상태: 채택
- 날짜: 2026-10-23

## 배경

플랫폼이 실습 환경을 만들고 터미널을 연결하려면 백엔드에서 Kubernetes API를 호출해야 한다. 개발 클러스터의 API 서버는 v1.37이다. client-java 호환표에는 1.37 열이 아직 없다.

## 선택지

1. 최신 client-java 27.0.1을 쓴다. 호환표에서 1.36까지 ✓이고, 1.37은 "-"(서버가 더 새 버전)에 해당한다.
2. 호환표가 1.37까지 갱신될 때까지 기다린다.
3. 호환표 ✓ 조합에 맞추려고 클러스터 버전을 낮춘다.

## 결정

`implementation 'io.kubernetes:client-java:27.0.1'`을 쓴다. Maven Central에 있으므로 저장소를 따로 추가하지 않는다.

## 이유

- "-"는 서버에만 있는 새 기능을 클라이언트가 못 쓴다는 뜻이다. Pod 생성, exec처럼 이전부터 있던 API는 그대로 쓸 수 있다고 본다.
- 클러스터를 낮추거나 기다리는 것은 개발을 멈추게 한다.
- `compile` 구성은 Gradle 7에서 제거됐다. `implementation`을 쓴다.

## 결과

- 1.37 서버를 실제로 호출하는 것은 아직 검증하지 않았다(SSH 터널 필요). 새 client-java 릴리스가 나오면 다시 확인한다.
- 전이 의존성(Jackson, Bouncy Castle)에 취약점 경고가 있다. 버전 고정은 따로 판단한다.
- `pods/exec`를 WebSocket으로 쓰려면 서비스 계정에 `get`과 `create` 권한이 모두 있어야 한다. 1.35부터 `AuthorizePodWebsocketUpgradeCreatePermission`이 기본으로 켜져 있다.
