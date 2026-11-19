# 문제 정보와 목록 API 작업 목록

관련 이슈: #63 · 결정: [decisions/020](../../decisions/020-문제-정보와-목록-API.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md), [decisions/016](../../decisions/016-fe-디자인-방향.md)

문제 정보에 분류, 난이도, 예상 시간, 요약을 더하고, 문제 목록 API가 검색, 필터, 정렬, 페이지를 지원하게 한다. 문제가 수백 개로 늘어나는 것을 기준으로 한다. fe 문제 목록과 홈 화면은 이 작업이 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- 분류 목록을 DB 테이블로 고정(처음 12개, ADR 020). 문제는 그 목록을 참조
- 문제마다 분류, 난이도(입문, 초급, 중급, 고급), 예상 시간(분), 요약(80자 이내)
- `GET /api/challenges`가 검색어, 분류, 난이도, 정렬, 페이지(20개)를 받고 전체 개수와 필터별 개수를 함께 응답
- `GET /api/challenges/{id}`로 문제 하나와 설명 전문을 조회
- 출제자가 `challenge.env`에 새 값을 쓰고 `register.sh`로 등록. 빠졌거나 틀린 값은 거절
- `sqli-login`에 값을 채워 개발 DB에 다시 등록하고 두 API로 확인

## 예외 상황

- 목록에 없는 분류 키로 등록: DB FK가 거절, 등록 transaction 전체가 취소됨
- `challenge.env`에 새 값이 빠졌거나 형식이 틀림(난이도 값, 0 이하 시간, 80자 넘는 요약): `register.sh`가 DB를 바꾸기 전에 거절
- 없는 정렬·난이도 값, 0 이하 페이지: 400 `VALIDATION_FAILED`
- 없는 분류 키로 필터: 결과 없음(400 아님). 분류는 DB에서 늘어나므로 API가 값을 고정하지 않음
- 범위를 넘은 페이지: 빈 `items`, 전체 개수와 필터별 개수는 그대로
- 검색어의 `%`, `_`: 와일드카드가 아니라 글자로 찾음
- 없는 문제 조회: 404 `CHALLENGE_NOT_FOUND`
- 승인 대기·거절 계정: 지금처럼 조회 가능. 비로그인은 401
- 다시 등록: 분류, 난이도, 예상 시간, 요약은 갱신. 처음 등록 시각과 NEW 여부는 그대로
- 내 상태(시작 전, 끝내지 못함, 완료) 필터와 칸: 실습 기록(#13)이 생긴 뒤 추가

## 작업

- [ ] 1. [docs] ADR 020(문제 정보, 분류 목록, 목록 API), 이 작업 목록, `data-model.md`(`challenge_categories`, `challenges` 컬럼) (확인: 사람이 정한 결정과 맞음)
- [ ] 2. [be] `openapi.yaml` 0.3.0: 목록 조건과 페이지 응답(`items`, `page`, `size`, `totalItems`, `totalPages`, `facets`), `GET /api/challenges/{id}` (테스트: OpenAPI lint)
- [ ] 3. [be] migration V8: `challenge_categories`(12개), `challenges`에 `category_key`(FK), `difficulty`(CHECK), `estimated_minutes`(CHECK > 0), `summary`(80자), 이미 있는 행은 임시 값, 개발 seed `test-web` 갱신 (테스트: 없는 분류 키·난이도 값·0 이하 시간 거절, 개발 seed 적용)
- [ ] 4. [be] `GET /api/challenges` 검색, 필터, 정렬, 페이지, 필터별 개수 (테스트: 가짜 문제 수십 개로 검색 대상 3곳, 같은 조건 "또는"·다른 조건 "그리고", 필터별 개수가 자기 조건을 빼고 셈, 0개 분류 포함, 정렬 3가지와 같은 값일 때 순서, 페이지 경계와 범위 밖, `%`·`_` 검색, 잘못된 값 400, NEW 14일 경계, 힌트·해답·스크립트 미포함)
- [ ] 5. [be] `GET /api/challenges/{id}` (테스트: `description` 포함, 없는 id 404, 힌트·해답·스크립트 미포함, 승인 대기 계정 조회, 비로그인 401)
- [ ] 6. [challenge] `hackforge-challenge-template`: `challenge.env` 예시에 새 값, `register.sh` 값 확인과 저장, README 형식 규칙 (확인: 개발 DB에 등록하면 목록에 새 값이 보임, 값 누락·형식 오류·없는 분류 키는 거절되고 DB가 그대로)
- [ ] 7. [challenge] `hackforge-challenge-sqli`: 분류 `sqli`, 난이도, 예상 시간, 요약을 채워 개발 DB에 다시 등록 (확인: 두 API 응답에 값이 보이고 처음 등록 시각은 그대로)
