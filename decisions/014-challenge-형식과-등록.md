# 014. Challenge 형식, 검증 스크립트 실행, 등록

- 상태: 채택
- 날짜: 2026-11-13

## 배경

Challenge 하나에는 Compose 프로젝트, 공격 검증 규칙, 정상 기능 테스트, 힌트, 해답, 방어 검증 최대 시도 횟수가 들어간다(product.md). 저장소는 문제마다 private repo로 두고 `app/`(학습자 환경에 복사)과 `meta/`(플랫폼 전용)로 나눈다는 것까지 [ADR 007](007-challenge-저장소.md)에서 정했다. 실습 환경은 `sysbox-runc` Pod 하나 안의 Docker Compose이고, Challenge 이미지 안의 `images.tar`를 시작할 때 `docker load`한다([ADR 012](012-실습-환경-수명-주기.md)). 이 ADR은 `meta/`에 무엇을 어떤 파일로 두는지, 검증 스크립트를 어디서 어떻게 실행하는지, 문제를 플랫폼에 어떻게 등록하는지를 정한다. 공격 검증(#9), 방어(#10), 방어 검증(#11)은 이 형식을 쓴다.

제약은 다음과 같다.

- 학습자는 실습 Pod 안에서 root 셸을 가진다. Challenge 이미지에 들어간 것은 모두 학습자가 볼 수 있다
- 실습 Pod는 외부 통신이 모두 막혀 있다([ADR 013](013-실습-pod-격리와-백엔드-권한.md)). #10에서 학습자가 코드를 고치면 Pod 안에서 다시 빌드한다
- 문제 등록 파이프라인(CI 빌드, registry)은 v1 범위 밖이다. 이미지는 수동으로 빌드해 노드에 import한다
- 실습 Pod 자원은 개발 VM 기준 CPU 500m, 메모리 512Mi다

## 선택지

검증 스크립트 실행 위치

1. 백엔드가 검증할 때만 실습 Pod에 exec로 들어가 스크립트를 stdin으로 실행
2. 문제마다 checker 이미지를 따로 만들어 실습 namespace에 Pod로 띄움

문제 등록

1. 등록 스크립트가 `meta/`를 읽어 플랫폼 DB에 upsert(psql)
2. 관리자 등록 API
3. 백엔드가 폴더나 ConfigMap을 주기적으로 읽어 동기화

방어 검증의 "기존 공격 재실행"

1. 출제자가 만든 exploit 스크립트를 플랫폼이 실행
2. 학습자가 보낸 요청을 기록했다가 다시 보냄

오프라인 재빌드

1. 의존성을 설치한 base 이미지 위에 소스만 `COPY`
2. 의존성 파일을 `app/`에 넣음(vendoring)
3. 의존성이 없는 스택만 씀

힌트 저장

1. 별도 테이블 `challenge_hints`
2. 컬럼 `hint_1`, `hint_2`, `hint_3`
3. `TEXT[]` 배열 컬럼

## 결정

검증 스크립트는 1번(Pod 안 exec), 등록은 1번(psql upsert), 기존 공격 재실행은 1번(exploit 스크립트), 오프라인 재빌드는 1번(base 이미지), 힌트는 1번(별도 테이블)으로 한다. 힌트는 공격과 방어에 각각 3단계를 둔다(2026-11-13 결정, product.md 유스케이스 4에 방어 힌트 추가).

### 저장소 구조

```
hackforge-challenge-<slug>/
├─ app/                       학습자 환경의 /app으로 복사됨
│  ├─ compose.yaml
│  └─ <서비스>/                Dockerfile.base, Dockerfile, 소스, 초기 데이터 SQL 등
├─ meta/                      플랫폼만 읽음. Challenge 이미지에 넣지 않음
│  ├─ challenge.env           SLUG, TITLE, MAX_DEFENSE_ATTEMPTS
│  ├─ description.md          문제 목록에 보이는 설명
│  ├─ hints/attack/1.md 2.md 3.md    방향 → 위치 → 공격 방법
│  ├─ hints/defense/1.md 2.md 3.md   방향 → 위치 → 고치는 방법
│  ├─ solution.md             해답(공격과 수정)
│  ├─ attack-check.sh         학습자의 공격이 성공했는지(#9)
│  ├─ exploit.sh              대표 공격을 다시 보냄(#11)
│  └─ functional-test.sh      정상 기능이 동작하는지(#11)
├─ hackforge/                 entrypoint.sh, ready.sh. 모든 문제 공통(template 제공)
├─ Dockerfile                 Challenge 이미지: docker:dind + app/ + images.tar + hackforge/
├─ build.sh
└─ register.sh
```

- `meta/challenge.env`는 셸 변수 형식이다. YAML을 쓰면 `register.sh`에 parser 설치가 필요해서 쓰지 않는다
- 이미지 이름은 `hackforge/challenge-<slug>:<tag>`이고 tag는 저장소 tag와 같게 한다

### 검증 스크립트 실행 계약

- POSIX `sh` 스크립트다. 플랫폼은 실습 Pod의 container에 exec로 들어가 스크립트 본문을 stdin으로 넘겨 실행하고, 작업 폴더는 `/app`이다. 스크립트가 Pod에 파일로 남지 않는다
- 출제자는 로컬에서 `app/` 폴더에 들어가 같은 스크립트를 실행해 확인한다
- 스크립트가 쓰는 것: `docker compose exec`(DB 조회, 로그 확인), `wget`과 `nc`로 compose가 publish한 `127.0.0.1:<포트>`에 요청, `sh` 기본 도구
- exit code 0은 "확인하려는 일이 일어남"이다. 마지막 출력 줄은 결과 메시지로 기록하고 학습자에게 보여 줄 수 있다. 60초를 넘기면 FAIL로 본다

| 스크립트 | 0의 뜻 | 쓰는 곳 |
|---|---|---|
| `attack-check.sh` | 학습자의 공격이 성공함 | 공격 검증 PASS(#9) |
| `exploit.sh` | 대표 공격이 아직 통함 | 방어 검증(#11) |
| `functional-test.sh` | 정상 기능이 모두 동작함 | 방어 검증(#11) |

- 방어 검증 PASS는 `exploit.sh`가 0이 아니고 `functional-test.sh`가 0인 경우다. 서비스가 죽어서 공격이 실패한 경우는 `functional-test.sh`가 걸러 낸다
- `exploit.sh`는 payload 중 하나라도 통하면 0이다. 마지막 출력 줄에 아직 통하는 payload를 적는다(예: "payload 4개 중 2개가 아직 통함: ...")
- 백엔드 권한에 `pods/exec`가 필요하다. #8(웹 터미널)에서 추가하는 권한과 같다(ADR 013)

### 형식 규칙

- 문제 하나는 취약점 하나를 다룬다. `exploit.sh`의 payload는 모두 그 취약점을 노리고, 같은 취약점을 노리는 대표 payload를 여러 개 넣는다. 여러 취약점을 다루려면 문제를 나눈다
- 공격 검증은 웹 요청을 거쳐서만 남는 Target 쪽 증거로 판정한다. 웹 터미널 입력은 보지 않는다. 학습자가 DB와 `app/`을 직접 볼 수 있으므로 값을 맞히는 판정(비밀번호, flag)은 쓰지 않는다
- Pod 안에서 다시 빌드하는 서비스의 `Dockerfile`은 `FROM <base 이미지>` 위에 소스 `COPY`만 한다. 의존성은 `Dockerfile.base`에서 설치하고, base 이미지도 `images.tar`에 넣는다
- 모든 서비스에 healthcheck를 두고 TCP로 확인한다(`pg_isready -h 127.0.0.1`, `mysqladmin ping -h 127.0.0.1`). DB 공식 이미지는 초기화 SQL을 실행하는 동안 unix socket으로만 임시 서버를 열기 때문에, TCP로 확인해야 초기 데이터가 들어간 뒤에 healthy가 된다
- 초기 데이터는 DB의 `/docker-entrypoint-initdb.d/`로 넣는다. 세션마다 빈 volume에서 시작하므로 매번 같은 초기 데이터가 들어간다
- 외부 인터넷이 필요한 기능은 넣지 않는다
- 로컬 확인: 네트워크를 끊고 `docker compose build`가 됨, `attack-check.sh`는 공격 전 FAIL·공격 후 PASS, `exploit.sh`는 고치기 전 PASS·고친 뒤 FAIL, `functional-test.sh`는 고치기 전과 뒤 모두 PASS

### 빌드와 등록

1. `build.sh <tag>`: `Dockerfile.base`로 base 이미지 빌드, `docker compose build`, 공개 이미지와 base 이미지와 서비스 이미지를 `images.tar`로 묶음, Challenge 이미지 빌드와 import용 파일 저장
2. 노드에 import: `sudo ctr -n k8s.io images import`. 사람이 한다. 운영 서버는 ADR 012의 미정 항목(이미지를 넣는 방법)을 따른다
3. `PSQL="<PSQL>" register.sh <tag>`: `<PSQL>`은 플랫폼 DB에 psql로 접속하는 명령([계정 운영 runbook](../infra/account-operations.md)의 placeholder)이다
   - `meta/`의 필수 파일(힌트 6개, 스크립트 3개 등)이 있는지 확인한다
   - 그 문제에 진행 중 세션이 있으면 거절한다. 진행 중 세션은 시작할 때의 이미지(`lab_sessions.image`)를 쓰는데 검증 스크립트는 DB에서 읽으므로, 옛 이미지에 새 스크립트가 도는 일을 막는다
   - 파일 내용은 psql 변수로 읽어(`\set`과 backtick) SQL 문자열을 직접 이어 붙이지 않는다
   - 한 transaction 안에서 `challenges`를 slug 기준으로 upsert하고, 그 문제의 힌트를 지운 뒤 다시 넣는다

### DB

- `challenges`에 추가: `description` TEXT, `solution` TEXT, `attack_check` TEXT, `exploit` TEXT, `functional_test` TEXT, `max_defense_attempts` SMALLINT(CHECK > 0), `updated_at` TIMESTAMPTZ. 모두 NOT NULL
- `challenge_hints`: `challenge_id`(FK, `ON DELETE CASCADE`), `stage`(`ATTACK`, `DEFENSE`), `position`(1~3, CHECK), `content` TEXT. PK는 (`challenge_id`, `stage`, `position`)
- 문제 숨김이나 삭제 컬럼은 두지 않는다. v1은 문제가 2~3개다

### API

- `GET /api/challenges`: `id`, `slug`, `title`, `description`을 id 순서로 응답한다. 힌트, 해답, 스크립트는 응답에 넣지 않는다
- 등록 API는 없다

### 첫 문제: `sqli-login`

- 스택: PHP 8 + Apache, MySQL 8.4. MySQL은 512Mi 안에 들어가도록 메모리 설정을 줄인다(`performance_schema=OFF`, 작은 buffer pool)
- 취약점: 로그인 쿼리가 입력을 이어 붙임(`... WHERE username = '$u' AND password_hash = SHA2('$p', 256)`). `admin' -- ` 등으로 관리자 비밀번호 없이 관리자로 로그인함
- 증거: 로그인에 성공하면 앱이 쿼리 결과의 `username`을 `login_log`에 기록한다. `admin`은 무작위 비밀번호의 hash만 있어서 정상 로그인으로는 기록이 생기지 않는다
- `exploit.sh`: `admin' -- `, `admin'#`, `' OR '1'='1' -- `, `' OR 1=1 LIMIT 1 -- `
- `functional-test.sh`: `guest` 로그인 성공, 틀린 비밀번호 거절, 이름에 따옴표가 있는 `o'neil` 로그인 성공. 따옴표를 막는 식으로 고치면 FAIL이다
- 최대 방어 검증 시도 5회

## 이유

- exec 방식은 추가 이미지와 네트워크 예외가 필요 없고, 출제자가 로컬에서 같은 스크립트로 확인할 수 있다. 검증 중에 학습자가 `ps`로 명령을 볼 수 있지만, 증거가 학습자가 root를 가진 환경 안에 있어서 조작을 막을 수 없다는 점은 checker 이미지도 같다. 학습 플랫폼이라 이 한계는 받아들인다
- 등록은 출제자와 관리자가 같은 사람이고 문제가 2~3개라 스크립트 하나로 충분하다. 등록 API는 관리자 로그인과 CSRF 처리가 스크립트에 들어가고, 동기화 방식은 아직 정하지 않은 운영 배포 구성(볼륨, ConfigMap 권한)에 묶인다. 나중에 자동화하면 `meta/` 형식과 DB는 두고 실행 주체만 CI로 옮긴다
- 학습자 요청 재전송은 Target 요청 기록(#8)과 공격 요청을 골라내는 규칙이 필요하고, 세션 cookie처럼 그 순간에만 유효한 값 때문에 단순 재전송이 실패할 수 있다
- payload를 하나라도 통하면 FAIL로 보는 것은 원인을 고쳤는지 확인하기 위해서다. 원인을 고치면 모든 payload가 막히고, 증상만 막으면 일부가 남는다. 너무 많이 막은 경우는 정상 기능 테스트가 잡는다
- base 이미지 방식은 Pod 안 재빌드가 소스 복사뿐이라 오프라인으로 되고 몇 초면 끝난다. vendoring은 저장소에 바이너리가 쌓이고 재빌드마다 설치가 반복된다
- 힌트는 #9, #11에서 몇 번째까지 봤는지 기록하므로 하나하나를 가리킬 수 있어야 한다. 배열 컬럼은 제1정규형에 맞지 않고, 번호 컬럼은 반복 그룹이다
- 방어가 이 플랫폼의 핵심이라 방어 단계에서 막혀도 해답 전에 단계적으로 도움을 받을 수 있어야 한다
- PHP + MySQL은 SQLi 교재에서 흔한 조합이라 자료가 많고 컴파일이 없다(2026-11-13 결정)

## 결과

- 백엔드: migration으로 컬럼과 `challenge_hints` 추가, `GET /api/challenges` 구현. 검증 실행은 #9, #11에서 만든다
- `hackforge-challenge-template`과 `hackforge-challenge-sqli` 저장소를 만든다(ADR 007)
- 등록은 수동이다. 빌드, import, 등록 명령을 출제자가 실행한다
- 진행 중 세션이 있는 문제는 다시 등록할 수 없다. 문제를 고치려면 세션이 끝나기를 기다린다
- 나중에 이미지 tag마다 검증 스크립트를 따로 보관하고 세션은 시작할 때의 버전 스크립트를 쓰게 바꾸면, 진행 중 세션이 있어도 등록할 수 있다. 버전 테이블이 하나 늘어서 v1에서는 하지 않고, 문제가 늘거나 등록이 잦아지면 추가한다(2026-11-13 결정)
- MySQL 메모리가 512Mi 안에 들어가는지 개발 VM에서 측정한다. 넘치면 실습 Pod 메모리 상향이나 MariaDB를 다시 검토한다
- 테스트 문제(`infra/lab-test-challenge`)는 클러스터 확인용으로 남기고, 개발 seed에는 FAIL하는 자리 채움 스크립트와 힌트를 넣는다
- 형식이 바뀌면 문제 저장소마다 PR이 필요하다(ADR 007)
