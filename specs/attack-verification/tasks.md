# 공격 검증과 단계별 힌트 작업 목록

관련 이슈: #9 · 결정: [decisions/023](../../decisions/023-공격-검증과-힌트.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md), [decisions/012](../../decisions/012-실습-환경-수명-주기.md)

플랫폼이 공격 성공을 판정하고, 막히면 공격 힌트를 하나씩 공개한다. 공격 검증 PASS나 건너뛰기로 방어 단계로 넘어간다. 이 목록은 백엔드까지이고, fe 실습 화면은 spec(작업 2)이 머지된 뒤 별도 이슈로 만든다.

## 완료 기준

- `lab_sessions`에 학습 단계(`ATTACK` → `DEFENSE`)와 공격 건너뜀 여부
- 공격 검증을 요청하면 `RUNNING`으로 접수되고, 백엔드가 `attack-check.sh`를 실습 Pod 안에서 실행해 `PASS`, `FAIL`, `ERROR`와 마지막 출력 줄을 저장. `ATTACK` 단계의 PASS는 `DEFENSE`로 넘어감
- 세션마다 검증은 한 번에 하나. 검증 기록을 최근 순으로 조회
- 공격 힌트를 1 → 2 → 3 순서로 공개하고 힌트마다 공개 시각을 기록. 공개한 힌트는 단계와 상관없이 다시 볼 수 있음
- 공격 단계에서 언제든 건너뛰면 `DEFENSE`로 넘어가고 건너뜀이 기록됨
- 검증, 힌트, 건너뛰기 요청이 활동으로 기록됨

## 예외 상황

- 세션이 `READY`가 아님: 검증, 힌트, 건너뛰기 409 `LAB_NOT_READY`
- 이미 실행 중인 검증이 있음(공격이든 방어든): 409. 동시에 두 요청이 와도 DB가 하나만 받음
- 스크립트가 0이 아닌 값으로 끝나거나 60초를 넘김: `FAIL`. 공격 단계 계속
- exec 실패(Pod 연결 실패 등): `ERROR`, 다시 시도 안내
- 검증 중 백엔드 재시작: 2분이 지난 `RUNNING`을 reconciler가 `ERROR`로 바꿈
- 검증 중 세션 종료: 실행 결과는 그대로 저장, 단계는 바꾸지 않음
- 힌트를 다 공개함: 409
- `DEFENSE` 단계에서 공격 힌트 공개나 건너뛰기: 409
- 다른 학습자의 세션이나 검증: 404

## 작업

- [ ] 1. [docs] ADR 023, 이 작업 목록, `data-model.md`(`lab_sessions.stage`·`attack_skipped`, `verifications`, `lab_session_hints`), product.md 유스케이스 4와 LabSession 개념 (확인: 사람이 정한 결정과 맞음)
- [ ] 2. [be] `openapi.yaml` 0.6.0: 공격 검증 요청·조회·목록, 힌트 공개·목록, 건너뛰기, 세션 응답의 `stage`·`attackSkipped`·공개한 공격 힌트 수, 새 오류 코드 (테스트: OpenAPI lint)
- [ ] 3. [be] migration V10, `LabCluster.runScript`(exec stdin, timeout, exit code와 stdout), 검증 실행(응답 뒤 별도 thread)과 `RUNNING` 복구 (테스트: 가짜 클러스터로 PASS·FAIL·ERROR·60초 초과, 마지막 줄 추출, 동시 요청 하나만, 재시작 뒤 복구, `ATTACK` PASS만 단계 변경)
- [ ] 4. [be] API: 공격 검증 요청·조회·목록, 힌트 공개·목록, 건너뛰기, 세션 응답 필드, 활동 기록 (테스트: 단계·상태별 허용과 409, 힌트 순서와 공개 시각, 다른 학습자 404, 활동 기록)
- [ ] 5. [be] clusterTest: 개발 클러스터의 실제 Pod로 테스트용 공격 검증 스크립트(파일이 있으면 PASS)가 공격 전 FAIL, 터미널로 파일을 만든 뒤 PASS와 `DEFENSE` 전환 (테스트: `./gradlew clusterTest`)
