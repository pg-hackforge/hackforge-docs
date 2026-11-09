# 계정 운영 runbook

관리자가 API 없이 서버에서 직접 하는 계정 작업 두 가지, 첫 관리자 만들기와 탈퇴 요청 처리의 절차다. 모두 개발 DB에서 실제로 실행한 명령이다.

- 결정: [ADR 011](../decisions/011-계정-규칙.md)
- 기준: hackforge-be migration V3까지(2026-11-09). `users`나 `spring_session` schema가 바뀌거나 `users`를 참조하는 테이블이 생기면 같은 PR에서 이 문서도 고친다.

## placeholder

| 이름 | 뜻 | 개발 환경 값 |
|---|---|---|
| `<PSQL>` | 플랫폼 DB에 psql로 접속하는 명령 | hackforge-be 폴더에서 `docker compose exec postgres psql -U hackforge` |
| `<BASE_URL>` | 백엔드 주소 | `http://127.0.0.1:8080` |

- 미정(결정 필요): 운영 DB의 위치와 접속 방법. 백엔드를 클러스터에 올릴 때 정하고([ADR 010](../decisions/010-db-postgresql-flyway.md) "결과") 위 표에 운영 값을 채운다.

## psql에서 지킬 것

- 이메일은 소문자로 저장돼 있다. 대상 이메일은 소문자로 적는다.
- 대상 이메일은 `\set email '...'`로 한 번만 적고 SQL에서는 `:'email'`로 쓴다. 같은 값을 여러 번 손으로 치다 틀리는 일을 막는다.
- 데이터를 바꾸는 SQL은 `begin;`과 `commit;` 사이에서 실행한다. 출력되는 행 수(`UPDATE 1`, `DELETE 1`)가 주석에 적은 값과 다르면 `commit;` 대신 `rollback;`한다.
- 역할은 로그인할 때 세션에 들어간다. DB에서 역할을 바꾸거나 계정을 지우면 그 사용자의 세션도 지운다. 세션 테이블 `spring_session`의 `principal_name`이 사용자 id(문자열)라서 id로 찾는다. 세션 속성(`spring_session_attributes`)은 FK `ON DELETE CASCADE`로 함께 지워진다.

## 1. 첫 관리자 만들기

관리자 API는 관리자만 부를 수 있어서 첫 관리자는 API로 만들 수 없다. 관리자가 될 사람이 평소처럼 가입하고, 서버 관리자가 psql로 역할을 `ADMIN`, 상태를 `APPROVED`로 바꾼다. 두 번째 관리자부터는 이 절차를 쓰지 않고 첫 관리자가 역할 변경 API(`PUT /api/admin/users/{id}/role`)로 바꾼다.

### 1.1 가입

화면(fe)에서 가입한다. fe가 나오기 전에는 서버에서 curl로 가입한다. 비밀번호는 셸 history에 남지 않게 `read -s`로 받는다. 비밀번호에 `"`나 `\`가 있으면 아래 JSON이 깨지므로 이 방법으로 가입할 때는 그 두 문자를 쓰지 않는다.

```bash
BASE=<BASE_URL>
JAR=$(mktemp)
curl -s -o /dev/null -c "$JAR" "$BASE/api/me"                 # 401이지만 CSRF cookie(XSRF-TOKEN)를 받음
xsrf() { awk '$6 == "XSRF-TOKEN" {print $7}' "$JAR"; }
read -rsp '비밀번호: ' PW; echo

curl -s -b "$JAR" -c "$JAR" -H "X-XSRF-TOKEN: $(xsrf)" -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@example.com\",\"password\":\"$PW\",\"name\":\"Admin\",\"nickname\":\"admin\",\"affiliation\":\"Hackforge\",\"privacyAgreed\":true}" \
  "$BASE/api/auth/signup"; echo
```

`"status":"PENDING","role":"LEARNER"`가 들어 있는 JSON이 나오면 된다. 400이면 `errors`에 어느 필드가 규칙에 안 맞는지 나온다(ADR 011 가입 정보 표).

### 1.2 승격

```bash
<PSQL>
```

```sql
\set email 'admin@example.com'
begin;
update users set role = 'ADMIN', status = 'APPROVED' where email = :'email';                  -- UPDATE 1
delete from spring_session where principal_name = (select id::text from users where email = :'email');  -- 0 이상
commit;
```

가입 직후라 로그인 세션이 없으면 `DELETE 0`이 정상이다. 이미 로그인해 있었다면 그 세션에는 `LEARNER`가 들어 있으므로 지워서 다시 로그인하게 한다.

### 1.3 확인

1.1의 셸에서 이어서 로그인하고 관리자 API를 부른다.

```bash
curl -s -b "$JAR" -c "$JAR" -H "X-XSRF-TOKEN: $(xsrf)" -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@example.com\",\"password\":\"$PW\"}" "$BASE/api/auth/login"; echo
curl -s -o /dev/null -w '%{http_code}\n' -b "$JAR" "$BASE/api/admin/users"
unset PW; rm -f "$JAR"
```

- 로그인 응답에 `"role":"ADMIN","status":"APPROVED"`가 있음
- 관리자 API가 `200`. 로그인 응답의 역할이 `LEARNER`이고 `403`이면 1.2에서 `UPDATE 0`이 나온 것(이메일 오타)이므로 1.2를 다시 함

## 2. 탈퇴 요청 처리

v1에는 탈퇴 API가 없어서 사용자가 관리자에게 탈퇴를 요청하고 서버 관리자가 DB에서 계정을 지운다. 지우면 이메일, 이름, 닉네임, 소속, 가입 메모 등 그 계정의 개인정보가 DB에서 없어지고, 같은 이메일과 닉네임으로 다시 가입할 수 있게 된다. 지금은 `users`를 참조하는 테이블이 없어서 `users` 행과 세션만 지우면 된다.

아래 세 가지는 v1.1 이메일 인증(#18)을 만들 때 정하고, 정하면 이 절차에 반영한다.

- 미정(결정 필요): 탈퇴 요청을 받는 창구와 요청자가 계정 주인인지 확인하는 방법
- 미정(결정 필요): 실습 기록(#13)이 생긴 뒤 탈퇴한 사용자의 기록을 지울지, 사용자를 알 수 없게 바꿔 남길지. 탈퇴 API(ADR 011)에도 반영함
- 미정(결정 필요): DB 백업(ADR 010)을 도입한 뒤 백업 안에 남은 개인정보를 어떻게 다룰지. 보관 기간은 개인정보 동의 문구와 함께 정함

### 2.1 대상 확인

```bash
<PSQL>
```

```sql
\set email 'user@example.com'
select id, email, name, nickname, affiliation, role, status, created_at from users where email = :'email';   -- 1 row
select count(*) from users where role = 'ADMIN' and email <> :'email';
```

- 첫 번째 결과가 1행이고 이름, 소속이 요청자와 맞는지 봄
- 대상이 `ADMIN`인데 두 번째 결과가 0이면 지우지 않음. 관리자가 한 명도 남지 않으면 승인과 역할 변경을 할 사람이 없어 1절을 다시 해야 함. 다른 사람을 먼저 관리자로 만든 뒤 지움

### 2.2 삭제

같은 psql 세션에서 이어서 실행한다.

```sql
begin;
delete from spring_session where principal_name = (select id::text from users where email = :'email');  -- 0 이상
delete from users where email = :'email';                                                               -- DELETE 1
commit;
```

세션을 먼저 지운다. `users` 행을 먼저 지우면 세션을 찾을 id가 없어진다. 세션을 남겨도 그 세션의 요청은 401이 되지만, 개인정보 삭제 요청이므로 세션도 남기지 않는다.

### 2.3 확인

```sql
select count(*) from users where email = :'email';                                                   -- 0
```

- 관리자 화면(`GET /api/admin/users?status=<삭제 전 상태>`) 목록에 없음
- 그 이메일로 로그인하면 401 `INVALID_CREDENTIALS`
