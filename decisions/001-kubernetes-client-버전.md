# 001. Kubernetes client: client-java 27.0.1

- 상태: 채택 (배경의 서버 v1.37은 [ADR 005](005-실습-환경-실행-기반.md)로 v1.35가 됨)
- 날짜: 2026-10-23

## 배경

플랫폼이 실습 환경을 만들고 터미널을 붙이려면 백엔드에서 Kubernetes API를 호출해야 한다. 당시 개발 클러스터의 API 서버는 v1.37이었는데, client-java 호환표에는 1.37 열이 아직 없었다.

## 선택지

1. 최신 client-java 27.0.1 사용. 호환표상 1.36까지 ✓, 1.37은 "-"(서버가 더 새 버전)
2. 호환표가 1.37까지 갱신될 때까지 대기
3. 호환표 ✓ 조합에 맞춰 클러스터 버전을 내림

## 결정

`implementation 'io.kubernetes:client-java:27.0.1'`을 쓴다. Maven Central에 있어서 repository를 따로 추가하지 않는다.

## 이유

- "-"는 서버에만 있는 새 기능을 client가 못 쓴다는 의미이고, Pod 생성이나 exec처럼 예전부터 있던 API는 그대로 쓸 수 있다고 판단함
- 클러스터를 내리거나 기다리면 개발이 멈춤
- `compile` configuration은 Gradle 7에서 제거됐으므로 `implementation` 사용

## 결과

- 실제 서버 호출은 아직 검증하지 않았다. 지금 클러스터(v1.35)는 호환표상 ✓이고, 첫 호출은 실습 환경 기능(#6)에서 확인한다.
- transitive dependency(Jackson, Bouncy Castle)에 취약점 경고가 있다. 버전을 pin할지는 따로 판단한다.
- `pods/exec`를 WebSocket으로 쓰려면 service account에 `get`과 `create` 권한이 모두 필요하다. 1.35부터 `AuthorizePodWebsocketUpgradeCreatePermission`이 기본으로 켜져 있다.
