# 계정 작업 목록

관련 이슈: #12 · 결정: [decisions/002](../../decisions/002-인증-방식.md), [decisions/010](../../decisions/010-db-postgresql-flyway.md), [decisions/011](../../decisions/011-계정-규칙.md)

v1 범위는 자가 가입만이다. 이메일 인증·비밀번호 재설정(v1.1, #18)과 GitHub·Google 로그인(v1.2, #19)은 별도 이슈로 둔다. 화면(fe)은 스택을 정한 뒤 만들고, 이 목록은 백엔드 API와 테스트까지만 다룬다.

## 완료 기준

- 이메일·비밀번호·이름·닉네임·소속·가입 메모(선택)·개인정보 동의로 가입하면 `PENDING`(승인 대기), 역할 `LEARNER`로 생성됨 (유스케이스 1)
- 관리자가 승인·거절하면 상태가 `APPROVED`·`REJECTED`로 바뀜. 거절한 계정도 나중에 승인 가능 (유스케이스 9)
- 관리자가 역할(`LEARNER`/`AUTHOR`/`ADMIN`)을 바꾸면 그 계정의 로그인 세션 전부 삭제. 자기 역할은 변경 불가 (유스케이스 14)
- 관리자가 임시 비밀번호를 발급하면 관리자에게 한 번만 보이고, 그 계정의 세션 전부 삭제, 잠금 해제 (유스케이스 15)
- 로그인한 사용자는 현재 비밀번호 확인 후 비밀번호 변경 가능. 지금 세션을 뺀 나머지 세션 삭제
- 대기·거절 계정도 로그인 가능, `GET /api/me`로 자기 상태 확인
- 비밀번호는 bcrypt hash로만 저장
- 서버 세션 + cookie(`HttpOnly`, `SameSite=Lax`, 운영은 `Secure`) + CSRF. 세션은 Spring Session JDBC(PostgreSQL)에 저장, 요청 없으면 30분 뒤 만료
- 세션에는 사용자 id와 역할만 저장. 승인 상태는 세션에 넣지 않음
- DB는 PostgreSQL, schema는 Flyway migration으로만 변경. 테스트는 Testcontainers PostgreSQL로 실행

## 예외 상황

- 이미 가입된 이메일 또는 닉네임: 가입 거절, 어느 항목이 중복인지 알려 줌
- 입력 규칙 위반(비밀번호 규칙, 길이, 닉네임 문자, 동의 안 함): 가입 거절, 필드별 사유 반환
- 이메일이나 비밀번호가 틀림: 어느 쪽인지 구분하지 않고 같은 문구로 거절
- 같은 계정으로 비밀번호 5번 연속 틀림(로그인 + 내 비밀번호 변경 합산): 15분 잠금. 잠긴 동안은 비밀번호를 확인하지 않고 거절하고 남은 시간을 알려 줌
  - 비밀번호 변경에서 틀려 잠기면 그 계정의 세션 전부 삭제. 세션을 가진 사람이 이 API로 brute force 해서 로그인 잠금을 우회하지 못하게 함
  - 로그인 실패로 잠기면 이미 로그인한 세션은 유지. 이메일만 아는 사람이 일부러 틀려서 실습 중인 사용자를 로그아웃시키지 못하게 함
- 관리자가 아닌 사용자가 관리자 API 호출: 403
- `APPROVED` 계정 거절 시도: 거절(계정 정지는 v1 범위 밖)
- 관리자가 자기 역할 변경 시도: 403
- CSRF token 없이 상태를 바꾸는 요청: 403
- 승인 전에 실습 시작 시도: #6에서 실습 시작 때 DB로 확인
- 미정(결정 필요): 개인정보 수집·이용 동의 문구(수집 항목, 목적, 보관 기간). fe 만들 때 정함

## 작업

- [x] 1. [be] `openapi.yaml`에 계정 API 추가: `POST /api/auth/signup`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`, `PUT /api/me/password`, `GET /api/admin/users?status=`, `POST /api/admin/users/{id}/approve`, `POST /api/admin/users/{id}/reject`, `PUT /api/admin/users/{id}/role`, `POST /api/admin/users/{id}/temporary-password`, 에러 응답 형식 (테스트: OpenAPI lint, hackforge-be#7)
- [x] 2. [be] PostgreSQL·Flyway·Testcontainers 세팅. H2 제거, `compose.yaml`(PostgreSQL), Spring Session JDBC 테이블을 Flyway로 생성, 세션 30분 (테스트: 앱 context가 Testcontainers PostgreSQL로 뜨고 migration 적용됨, CI 통과, hackforge-be#10)
- [x] 3. [be] `users` 테이블, 가입·로그인·로그아웃·`GET /api/me`. 입력 검증, bcrypt, CSRF(SPA용 cookie 방식), 세션 cookie 속성, 세션에는 id·역할만 (테스트: 가입 시 `PENDING`·`LEARNER`, 중복 이메일·닉네임 거절, 규칙 위반 거절, 로그인 실패 문구 동일, 로그아웃 후 401, CSRF 없으면 403, cookie 속성, hackforge-be#13)
- [ ] 4. [be] 계정 잠금(로그인 실패) (테스트: 5번째 실패에 잠김, 잠긴 동안 맞는 비밀번호도 거절, 15분 뒤 해제, 성공하면 횟수 초기화, 로그인 실패로 잠겨도 기존 세션 유지)
- [ ] 5. [be] 관리자 API: 계정 목록(상태 필터, 기본 `PENDING`), 승인, 거절 (테스트: 관리자만 호출 가능, 허용된 상태 전이만 됨, `APPROVED` 거절 불가)
- [ ] 6. [be] 역할 변경, 임시 비밀번호 발급, 내 비밀번호 변경 (테스트: 자기 역할 변경 403, 역할 변경·임시 비밀번호 발급 후 대상의 기존 세션 무효, 임시 비밀번호가 규칙을 만족하고 잠금 해제됨, 현재 비밀번호 틀리면 거절, 성공하면 다른 세션만 무효, 틀린 횟수가 로그인 실패와 합산돼 5번째에 잠기고 그 계정 세션 전부 무효, 잠긴 동안은 현재 비밀번호를 확인하지 않고 거절)
- [ ] 7. [docs] `infra/`에 계정 운영 절차: 첫 관리자 승격(psql), 탈퇴 요청 처리 (확인: 개발 DB에서 절차대로 해 보고 관리자 API 동작 확인)
