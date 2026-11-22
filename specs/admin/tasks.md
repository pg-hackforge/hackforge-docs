# 관리와 기록 작업 목록

관련 이슈: #13 · 결정: [decisions/026](../../decisions/026-관리와-기록.md), [decisions/012](../../decisions/012-실습-환경-수명-주기.md), [decisions/025](../../decisions/025-방어-검증과-해답.md)

관리자는 세션 목록을 보고 강제 종료하고, 모든 세션의 기록을 본다. 학습자는 자기 지난 실습 기록과 그때 연 해답을 다시 본다. 세션 상태가 바뀔 때마다 주체와 함께 기록하고, Prometheus·Grafana로 Pod·컨테이너 CPU·메모리를 본다. 이 목록은 백엔드와 infra까지이고, fe 화면은 백엔드가 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- 관리자 세션 목록에 누가 어떤 문제를 어느 단계에서 하는지 보임. 기본은 진행 중, 전체로 바꾸면 종료한 세션도
- 관리자가 강제 종료하면 환경이 삭제되고 열린 터미널도 끊김. 종료 사유 `ADMIN`
- 세션 상태가 바뀔 때마다 이전 → 다음 상태, 주체(학습자, 관리자, 시스템), 시각이 남음
- 관리자는 모든 세션의, 학습자는 자기 세션의 검증·재배포·힌트·상태 기록을 봄
- 학습자는 지난 세션에서 연 해답을 다시 봄
- Grafana에서 노드와 실습 namespace별 CPU·메모리를 7일 동안 볼 수 있음

## 예외 상황

- 관리자가 아닌 사용자의 관리자 API: 403
- 이미 종료 중이거나 끝난 세션 강제 종료: 지금 상태를 그대로 줌
- 관리자가 남의 세션에 바꾸는 요청(검증, 파일, 재배포, 초기화, 종료): 지금처럼 404
- 해답을 연 적 없는 세션의 해답 다시 보기: 409 `SOLUTION_LOCKED`
- 주체를 적지 않은 변경(reconciler, 시작할 때 복구): `SYSTEM`
- Prometheus·Grafana가 내려가도 플랫폼은 그대로 동작함

## 작업

- [x] 1. [docs] ADR 026, 이 작업 목록, `data-model.md`(`session_events`, 종료 사유 `ADMIN`), product.md 유스케이스(내 실습 기록) (확인: 사람이 정한 결정과 맞음)
- [x] 2. [be] `openapi.yaml` 0.9.0: 학습자 세션 목록, 상태 기록, 해답 다시 보기, 관리자 세션 목록·강제 종료, 조회 API의 관리자 허용, 종료 사유 `ADMIN` (테스트: OpenAPI lint)
- [x] 3. [be] migration V13(`session_events`, trigger, 종료 사유 `ADMIN`), 요청마다 주체 기록, 학습자 세션 목록, 상태 기록·해답 다시 보기, 관리자 세션 목록·강제 종료, 조회 API의 관리자 허용 (테스트: 상태 변경마다 기록과 주체(학습자 시작·종료, 관리자 종료, reconciler는 시스템), 목록 필터·페이지·순서, 강제 종료 `ADMIN`과 이미 끝난 세션, 관리자 아님 403, 관리자의 남의 세션 조회는 되고 변경은 404, 해답 다시 보기, Postman)
- [x] 4. [infra] 개발 클러스터에 Prometheus·Grafana 가벼운 설치(Alertmanager 없음, 30초, 7일, local-path-provisioner 기본 StorageClass와 PVC. `cluster-setup.md`에 local-path-provisioner 절차), 실습 namespace별 CPU·메모리 대시보드, `infra/monitoring.md` runbook과 자원 사용량 측정 (확인: Grafana에서 실습 세션 하나의 CPU·메모리가 보이고 Prometheus·Grafana 메모리 실측)
