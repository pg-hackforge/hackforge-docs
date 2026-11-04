# 010. DB는 PostgreSQL, schema는 Flyway

- 상태: 채택
- 날짜: 2026-11-04

## 배경

지금 백엔드는 개발용 H2만 쓰고 운영 DB는 정하지 않았다. 계정 기능(#12)에서 사용자 테이블과 Spring Session JDBC 테이블([ADR 002](002-인증-방식.md))을 만들고, 실습 환경(#6)에서는 "학습자당 진행 중인 세션 1개"를 앱 코드가 아니라 DB constraint로 보장해야 한다. 앱에서 "조회 → 없으면 생성"으로 막으면, [실습 시작]을 빠르게 두 번 누르거나 탭 두 개에서 누를 때 두 요청이 모두 통과할 수 있다.

이 constraint는 "진행 중인 행끼리만 unique"라서 partial unique index가 필요하다.

```sql
CREATE UNIQUE INDEX ... ON lab_session (user_id) WHERE status <> 'DELETED';
```

## 선택지

DB

1. PostgreSQL
2. MySQL / MariaDB
3. 당분간 H2 파일 모드 유지

schema 관리

1. Flyway (SQL 파일 migration)
2. Liquibase (XML/YAML changelog, DB별 SQL 생성)
3. JPA `ddl-auto` (entity를 보고 Hibernate가 생성)

## 결정

- dev·test·prod 모두 PostgreSQL. major 버전은 셋 다 같게 pin
- schema는 Flyway SQL migration(`src/main/resources/db/migration/V<번호>__<이름>.sql`)으로만 변경. 이미 적용한 파일은 고치지 않고 새 파일을 추가. `ddl-auto`는 `validate`
- dev DB는 Windows의 Docker Desktop에서 실행(`hackforge-be/compose.yaml`). 테스트는 Testcontainers로 실제 PostgreSQL을 띄움
- H2는 의존성에서 제거

## 이유

- PostgreSQL은 partial index를 지원함. MySQL은 없어서 "진행 중일 때만 값이 들어가는 generated column + unique"로 우회해야 하고, H2도 지원하지 않음
- PostgreSQL은 DDL도 트랜잭션으로 묶여서 migration이 중간에 실패하면 전부 rollback됨. MySQL은 반쯤 바뀐 상태로 남음
- PostgreSQL은 연결마다 프로세스를 띄워 메모리 비용이 연결 수에 비례하지만, 백엔드는 connection pool(HikariCP 기본 10개)을 쓰므로 30명 확장 설계에서도 연결은 수십 개 수준. 실습 Pod 메모리에 비하면 작음
- partial index처럼 세부 constraint를 직접 써야 하므로 SQL을 그대로 쓰는 Flyway가 맞음. Liquibase의 장점(여러 DB용 SQL 생성, 무료 rollback)은 DB가 하나면 쓸 곳이 적고, `ddl-auto`는 이런 constraint를 표현하지 못하고 운영에서 무엇이 바뀔지 미리 볼 수 없음
- 테스트를 H2로 돌리면 H2에서는 통과하고 PostgreSQL에서 깨지는 경우가 생김. Testcontainers는 CI(GitHub Actions ubuntu runner)에서도 Docker로 그대로 돎
- 앱은 접속 주소만 보므로 dev DB를 Docker Desktop에 둬도 운영(클러스터 안)과 설정값만 다름. 개발 VM(4GB)에 DB를 올리면 실습 Pod와 메모리를 나눠 써야 하고, Windows에서 도는 백엔드에서 VM으로 연결을 열어야 함

## 결과

- Spring Session JDBC 테이블도 Flyway 파일로 만든다(`spring.session.jdbc.initialize-schema=never`).
- 서버를 재시작해도 로그인이 유지된다. ADR 002 "결과"의 H2 메모리 모드 문제는 없어진다.
- 백엔드 빌드와 테스트에 Docker가 필요하다.
- 백엔드를 클러스터에 올릴 때(운영 구성) 아래를 함께 정하고 `infra/`에 runbook으로 남긴다. dev DB(Docker Desktop)로는 검증되지 않는 부분이다.
  - storage: kubeadm 클러스터에는 기본 StorageClass가 없음. DB용 PersistentVolume을 준비하고 SSD 위에 둠(HDD는 fsync가 느려 [ADR 008](008-개발-VM-실행-환경.md)에서 etcd가 멈췄음)
  - 격리: 같은 클러스터에서 학습자가 셸을 가진 실습 Pod가 돎. NetworkPolicy로 실습 namespace에서 플랫폼 DB로 가는 경로를 막음
  - 백업: 노드가 하나라 정기 dump를 클러스터 밖에 둠
  - 재시작, major 버전 업그레이드 절차
