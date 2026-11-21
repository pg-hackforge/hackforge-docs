# 방어 검증 작업 목록

관련 이슈: #11 · 결정: [decisions/025](../../decisions/025-방어-검증과-해답.md), [decisions/023](../../decisions/023-공격-검증과-힌트.md), [decisions/024](../../decisions/024-방어-IDE-재배포-초기화.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md), [decisions/012](../../decisions/012-실습-환경-수명-주기.md)

방어 단계에서 방어 검증을 요청하면 기존 공격(`exploit.sh`)과 정상 기능 테스트(`functional-test.sh`)를 실행해 판정한다. 실패가 최대 횟수만큼 쌓이면 해답을 열 수 있다. 첫 PASS로 실습 완료를 기록하고, 입력이 없으면 5분 뒤 종료한다. 이 목록은 백엔드까지이고, fe 실습 화면은 백엔드가 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- 방어 단계에서 방어 검증을 요청하면 비동기로 `exploit.sh`와 `functional-test.sh`를 둘 다 실행하고, 공격이 모두 막히고 정상 기능이 동작하면 `PASS`
- 결과에 보안·기능 테스트 통과 여부와 각 마지막 줄(아직 통하는 payload, 실패한 기능), 본 방어 힌트 수, 해답 확인 후 여부
- 방어 검증 시도 횟수(`PASS`, `FAIL`)가 세션 응답에 보이고, `FAIL`이 최대 횟수만큼 쌓이면 해답을 열 수 있음. 연 시각 기록
- 해답을 연 뒤의 PASS는 "해답 확인 후 PASS"
- 첫 PASS에 실습 완료 시각 기록. 완료 뒤 입력이 없으면 5분 뒤 종료, 5분 안에 입력이 있으면 그 뒤로는 30분 기준(종료 사유는 둘 다 `IDLE`)
- 방어 검증 요청과 해답 열기가 활동으로 기록됨

## 예외 상황

- 세션이 `READY`가 아님: 409 `LAB_NOT_READY`
- 공격 단계에서 방어 검증: 409 `WRONG_LAB_STAGE`
- 검증·재배포·초기화 중 하나가 실행 중: 409 `LAB_JOB_RUNNING`
- 스크립트가 60초를 넘김: 그 테스트는 통과 아님, 결과 `FAIL`, "60초 안에 끝나지 않았어요"
- exec 실패: `ERROR`, 시도 횟수에 세지 않음, 다시 시도 안내
- 실행 중 백엔드 재시작: 시작할 때 `ERROR`로. 안전망으로 reconciler가 3분 지난 방어 검증 `RUNNING`을 `ERROR`로
- 해답을 아직 열 수 없음: 409. 세션이 `READY`가 아님: 409 `LAB_NOT_READY`(종료한 세션의 해답은 #13에서 정함)
- 최대 횟수를 넘긴 뒤나 해답을 본 뒤에도 방어 검증은 계속 받음
- 완료 뒤 다시 PASS: 완료 시각은 그대로

## 작업

- [x] 1. [docs] ADR 025, 이 작업 목록, `data-model.md`(`verifications` 방어 컬럼, `lab_sessions.completed_at`, `solution_viewed_at`), product.md 유스케이스 6·예외 상황·개념 (확인: 사람이 정한 결정과 맞음)
- [x] 2. [be] `openapi.yaml` 0.8.0: 방어 검증 요청, 검증 응답 방어 필드, 해답 열기, 세션 응답(시도 횟수, 최대 횟수, 해답 열 수 있음, 해답 연 시각, 완료 시각), 오류 코드 (테스트: OpenAPI lint)
- [x] 3. [be] migration V12, 방어 검증 실행(두 스크립트, 판정, 메시지, 시도 횟수, 3분 복구), 해답 열기, 실습 완료와 완료 뒤 5분 종료, 세션 응답 (테스트: 가짜 클러스터로 PASS·보안 FAIL·기능 FAIL·둘 다 FAIL·시간 초과·exec 실패, 시도 횟수에 `ERROR` 제외, 해답 잠김 409와 최대 횟수 뒤 열기, `after_solution`, 첫 PASS만 완료 시각, 완료 뒤 5분 종료와 입력 뒤 30분 종료, 단계·상태·동시 실행 409, 활동)
- [x] 4. [be] clusterTest: 개발 클러스터의 실제 Pod에서 테스트용 스크립트로 방어 검증 FAIL → 터미널에서 고침 → PASS와 완료 시각 (테스트: `./gradlew clusterTest`)
- [x] 5. [be] Postman "9. 실습"에 방어 검증, 결과, 해답 요청. 개발 백엔드에서 실제 sqli-login으로 FAIL → 해답대로 고쳐 재배포 → PASS 확인(공격 문자열과 고친 코드는 PR에 적지 않음) (확인: newman)
