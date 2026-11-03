# 계정 작업 목록

관련 이슈: #12 · 결정: [decisions/002](../../decisions/002-인증-방식.md), [decisions/010](../../decisions/010-db-postgresql-flyway.md), [decisions/011](../../decisions/011-계정-규칙.md)

v1 범위는 자가 가입만이다. 이메일 인증·비밀번호 재설정(v1.1)과 GitHub·Google 로그인(v1.2)은 따로 이슈로 둔다. 화면(fe)은 스택을 정한 뒤 만든다. 이 목록은 백엔드 API와 테스트로 끝낸다.

## 완료 기준

- 이메일·비밀번호·이름·닉네임·소속·가입 메모(선택)·개인정보 동의로 가입하면 `PENDING`(승인 대기), 역할 `LEARNER`가 된다 (유스케이스 1)
- 관리자가 승인·거절하면 상태가 `APPROVED`·`REJECTED`로 바뀐다. 거절한 계정은 나중에 승인할 수 있다 (유스케이스 9)
- 관리자가 역할(`LEARNER`/`AUTHOR`/`ADMIN`)을 바꾸면 그 계정의 로그인 세션이 모두 지워진다. 자기 자신의 역할은 바꿀 수 없다 (유스케이스 14)
- 관리자가 임시 비밀번호를 발급하면 관리자에게 한 번만 보이고, 그 계정의 세션이 모두 지워지고 잠금이 풀린다 (유스케이스 15)
- 로그인한 사용자는 현재 비밀번호를 확인한 뒤 비밀번호를 바꿀 수 있다. 지금 세션을 뺀 나머지 세션이 지워진다
- 대기·거절 계정도 로그인할 수 있고, `GET /api/me`로 자기 상태를 본다
- 비밀번호는 bcrypt 해시로만 저장한다
- 서버 세션 + 쿠키(`HttpOnly`, `SameSite=Lax`, 운영은 `Secure`) + CSRF 보호. 세션은 Spring Session JDBC(PostgreSQL)에 두고, 요청이 없으면 30분 뒤 만료된다
- 세션에는 사용자 id와 역할만 둔다. 승인 상태는 세션에 담지 않는다
- DB는 PostgreSQL, 스키마는 Flyway 마이그레이션으로만 바꾼다. 테스트는 Testcontainers의 PostgreSQL로 돈다

## 예외 상황

- 이미 가입된 이메일 또는 닉네임: 가입을 거절하고 어느 항목이 중복인지 알려 준다
- 입력 규칙 위반(비밀번호 규칙, 길이, 닉네임 문자, 동의 안 함): 가입을 거절하고 항목별 이유를 알려 준다
- 이메일이나 비밀번호가 틀림: 어느 쪽이 틀렸는지 구분하지 않고 같은 문구로 거절한다
- 같은 계정으로 5번 연속 로그인 실패: 15분 잠근다. 잠긴 동안은 비밀번호를 확인하지 않고 거절하며 남은 시간을 알려 준다
- 관리자가 아닌 사용자가 관리자 API를 부름: 403
- `APPROVED` 계정을 거절하려 함: 거절한다(계정 정지는 v1 범위 밖)
- 관리자가 자기 역할을 바꾸려 함: 403
- CSRF 토큰 없이 상태를 바꾸는 요청: 403
- 승인 전에 실습을 시작하려 함: #6에서 실습 시작 때 DB로 확인한다
- 미정 — 결정 필요: 개인정보 수집·이용 동의 안내 문구(수집 항목, 목적, 보관 기간). fe를 만들 때 정한다

## 작업

- [ ] 1. [be] `openapi.yaml`에 계정 API 추가 — `POST /api/auth/signup`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`, `PUT /api/me/password`, `GET /api/admin/users?status=`, `POST /api/admin/users/{id}/approve`, `POST /api/admin/users/{id}/reject`, `PUT /api/admin/users/{id}/role`, `POST /api/admin/users/{id}/temporary-password`. 오류 응답 형식 포함 — 테스트: OpenAPI 문법 검사
- [ ] 2. [be] PostgreSQL·Flyway·Testcontainers 기반. H2 제거, `compose.yaml`(PostgreSQL), Spring Session JDBC 테이블을 Flyway로 생성, 세션 30분 — 테스트: 앱 컨텍스트가 Testcontainers PostgreSQL로 뜨고 마이그레이션이 적용됨, CI 통과
- [ ] 3. [be] `users` 테이블과 가입·로그인·로그아웃·`GET /api/me`. 입력 검사, bcrypt, CSRF(SPA용 쿠키 방식), 세션 쿠키 속성, 세션에는 id·역할만 — 테스트: 가입 → `PENDING`·`LEARNER`, 중복 이메일·닉네임 거절, 규칙 위반 거절, 로그인 성공·실패 같은 문구, 로그아웃 후 401, CSRF 없으면 403, 쿠키 속성
- [ ] 4. [be] 로그인 실패 잠금 — 테스트: 5번째 실패에 잠김, 잠긴 동안 맞는 비밀번호도 거절, 15분 뒤 풀림, 성공하면 횟수 초기화
- [ ] 5. [be] 관리자 API: 계정 목록(상태 필터, 기본 `PENDING`)·승인·거절 — 테스트: 관리자만 호출 가능, 허용된 상태 전이만 됨, `APPROVED` 거절 불가
- [ ] 6. [be] 역할 변경·임시 비밀번호 발급·내 비밀번호 변경 — 테스트: 자기 역할 변경 403, 역할 변경·임시 비밀번호 발급 후 대상의 기존 세션 무효, 임시 비밀번호가 규칙을 만족하고 잠금이 풀림, 비밀번호 변경은 현재 비밀번호가 틀리면 거절하고 다른 세션만 무효
- [ ] 7. [docs] `infra/`에 계정 운영 절차 — 첫 관리자 승격(psql), 탈퇴 요청 처리 — 확인: 개발 DB에서 절차대로 해 보고 관리자 API가 동작함
