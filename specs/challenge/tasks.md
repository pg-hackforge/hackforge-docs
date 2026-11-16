# Challenge 형식과 첫 문제 작업 목록

관련 이슈: #7 · 결정: [decisions/007](../../decisions/007-challenge-저장소.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md)

Challenge 저장소 형식, 검증 스크립트 실행 계약, 등록 방식을 정하고, 첫 문제(SQLi 로그인 우회)를 그 형식으로 만들어 문제 목록에 올린다. 검증 스크립트를 실제로 실행하는 기능은 공격 검증(#9)과 방어 검증(#11)에서, 힌트 공개는 #9와 #10에서 만든다. 여기서는 스크립트를 로컬과 개발 VM에서 직접 실행해 확인한다. 화면(fe)은 스택을 정한 뒤 별도 이슈로 만든다.

## 완료 기준

- Challenge 형식 확정: Compose 프로젝트, 공격 검증·exploit·정상 기능 테스트 스크립트, 공격 힌트 3개, 방어 힌트 3개, 해답, 방어 검증 최대 시도 횟수 (ADR 014)
- 공격·방어 검증은 Target 쪽 증거로만 판정. 웹 터미널 입력은 안 봄
- private repo `hackforge-challenge-template`(GitHub Template), `hackforge-challenge-sqli` 생성. `app/`과 `meta/` 분리 (ADR 007)
- 첫 문제(`sqli-login`)를 이 형식으로 작성하고 로컬 Docker Compose로 공격·방어 확인
- 출제자가 빌드, import, 등록하면 `GET /api/challenges` 목록에 나타남 (유스케이스 13)
- 개발 VM 실습 Pod(메모리 512Mi)에서 첫 문제가 `READY`가 되고 스크립트 3개가 기대대로 동작함

## 예외 상황

- 그 문제에 진행 중 세션이 있는데 다시 등록: `register.sh`가 거절. 세션이 끝난 뒤 등록
- `meta/` 필수 파일(힌트 6개, 스크립트 3개, `challenge.env`, `description.md`, `solution.md`) 누락: `register.sh`가 거절, DB는 바뀌지 않음
- 같은 slug로 다시 등록: 이미지 tag, 설명, 힌트, 해답, 스크립트를 갱신. 진행 중이 아닌 옛 세션 기록은 그대로
- 검증 스크립트가 60초를 넘김: FAIL로 봄(실행은 #9, #11)
- Pod 안에서 다시 빌드할 때 외부 통신 없음: 재빌드 대상 서비스는 base 이미지 위 `COPY`만 하므로 오프라인으로 빌드됨
- 미정(실측 후 결정): MySQL을 포함한 첫 문제가 메모리 512Mi 안에 들어가는지. 작업 7에서 측정하고, 넘치면 실습 Pod 메모리 상향이나 MariaDB를 다시 검토
- 미정(결정 필요): 운영 서버에 Challenge 이미지를 넣는 방법. 운영 서버 구성 때 정함 (ADR 012)

## 작업

- [x] 1. [docs] ADR 014(Challenge 형식, 검증 스크립트 실행, 등록), 이 작업 목록, `data-model.md`(`challenges` 컬럼, `challenge_hints`), product.md(방어 힌트, Challenge 구성), #9·#10·#11 완료 기준 갱신 (확인: 사람이 정한 결정과 맞음, #40)
- [x] 2. [be] `openapi.yaml`의 `ChallengeResponse`에 `description` 추가 (테스트: OpenAPI lint, hackforge-be#34)
- [x] 3. [be] migration V7로 `challenges` 컬럼 추가와 `challenge_hints` 생성, 개발 seed의 `test-web`에 자리 채움 값 (테스트: `stage`·`position`·`max_defense_attempts` CHECK 위반 거절, 같은 단계·번호 힌트 중복 거절, 문제 삭제 시 힌트도 삭제, 개발 seed 적용, hackforge-be#35)
- [x] 4. [be] `GET /api/challenges` (테스트: id 순서, `description` 포함, 힌트·해답·스크립트 미포함, 승인 대기 계정도 조회, 비로그인 401, hackforge-be#35)
- [ ] 5. [challenge] `hackforge-challenge-template` 생성: 저장소 구조, 공통 `hackforge/entrypoint.sh`·`ready.sh`, Challenge `Dockerfile`, `build.sh`, `register.sh`, CI(빌드와 로컬 확인), README(형식 규칙, 로컬 확인 방법) (확인: 예시 문제로 빌드, 개발 DB에 등록하면 `GET /api/challenges`에 보임, 다시 등록하면 갱신, 진행 중 세션이 있거나 필수 파일이 없으면 거절)
- [ ] 6. [challenge] `hackforge-challenge-sqli` 작성: PHP + Apache, MySQL 8.4, `login_log` 증거, 스크립트 3개, 공격·방어 힌트, 해답 (확인: 네트워크를 끊고 `docker compose build`, `attack-check.sh` 공격 전 FAIL·후 PASS, `exploit.sh` 수정 전 PASS·후 FAIL, `functional-test.sh` 수정 전후 PASS, 따옴표를 막는 수정은 `functional-test.sh` FAIL, CI 통과)
- [ ] 7. [docs] 개발 VM에 `sqli-login`을 import하고 등록, 실습 시작부터 `READY`까지 시간과 메모리 측정, `kubectl exec`로 스크립트 3개 실행, 결과를 `infra/`에 기록 (확인: 512Mi 안에서 동작. 넘치면 `미정(결정 필요):`로 기록)
