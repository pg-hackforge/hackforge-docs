# 010. DB는 PostgreSQL, 스키마는 Flyway

- 상태: 채택
- 날짜: 2026-11-04

## 배경

지금 백엔드는 개발용 H2만 쓰고 운영 DB는 미정이다. 계정 기능(#12)에서 사용자 테이블과 Spring Session JDBC 테이블([ADR 002](002-인증-방식.md))을 만든다. 실습 환경(#6)에서는 "학습자당 진행 중인 세션 1개"를 앱 코드가 아니라 DB 제약으로 보장해야 한다. [실습 시작]을 두 번 빠르게 누르거나 탭 두 개에서 누르면, 앱에서 "조회 → 없으면 생성"으로 막아도 두 요청이 모두 통과할 수 있기 때문이다.

이 제약은 "진행 중인 행끼리만 유일"이므로 부분 유니크 인덱스가 필요하다.

```sql
CREATE UNIQUE INDEX ... ON lab_session (user_id) WHERE status <> 'DELETED';
```

## 선택지

DB

1. PostgreSQL
2. MySQL / MariaDB
3. H2 파일 모드를 당분간 유지

스키마 관리

1. Flyway (SQL 파일 마이그레이션)
2. Liquibase (XML/YAML 변경 기록, DB별 SQL 생성)
3. JPA `ddl-auto` (엔티티를 보고 Hibernate가 생성)

## 결정

- 개발·테스트·운영 모두 PostgreSQL을 쓴다. 메이저 버전은 셋 다 같게 고정한다.
- 스키마는 Flyway SQL 마이그레이션(`src/main/resources/db/migration/V<번호>__<이름>.sql`)으로만 바꾼다. 이미 적용한 파일은 고치지 않고 새 파일을 더한다. `ddl-auto`는 `validate`로 둔다.
- 개발 DB는 Windows의 Docker Desktop에서 띄운다(`hackforge-be/compose.yaml`). 테스트는 Testcontainers로 진짜 PostgreSQL을 띄운다.
- H2는 의존성에서 뺀다.

## 이유

- PostgreSQL은 부분 인덱스를 지원한다. MySQL에는 없어서 "진행 중일 때만 값이 들어가는 계산 컬럼 + 유니크"로 우회해야 한다. H2도 지원하지 않는다.
- PostgreSQL은 DDL도 트랜잭션으로 묶인다. 마이그레이션이 중간에 실패하면 통째로 되돌아간다. MySQL은 반쯤 바뀐 채 남는다.
- 연결마다 프로세스를 쓰는 PostgreSQL의 메모리 비용은 연결 수에 비례한다. 백엔드는 연결 풀(HikariCP 기본 10개)을 쓰므로 30명 확장 설계에서도 연결은 수십 개다. 실습 Pod가 쓰는 메모리에 비하면 작다.
- 부분 인덱스처럼 세부 제약을 직접 써야 하므로 SQL을 그대로 쓰는 Flyway가 맞다. Liquibase의 장점(여러 DB용 SQL 생성, 무료 롤백)은 DB 하나만 쓰면 쓸 곳이 적다. `ddl-auto`는 이런 제약을 표현하지 못하고, 운영에서 무엇이 바뀔지 미리 볼 수 없다.
- 테스트를 H2로 돌리면 H2에서는 통과하고 PostgreSQL에서 깨지는 일이 생긴다. Testcontainers는 CI(GitHub Actions Ubuntu 러너)에서도 Docker로 그대로 돈다.
- 앱은 접속 주소만 보므로 개발 DB를 Docker Desktop에 둬도 운영(클러스터 안)과 설정값만 다르다. 개발 VM(4GB)에 DB를 올리면 실습 Pod와 메모리를 나눠 쓰고, Windows에서 도는 백엔드에서 VM으로 연결을 열어야 한다.

## 결과

- Spring Session JDBC 테이블도 Flyway 파일로 만든다(`spring.session.jdbc.initialize-schema=never`).
- 서버를 재시작해도 로그인이 유지된다. ADR 002 "결과"의 H2 메모리 모드 문제가 없어진다.
- 백엔드 빌드와 테스트에 Docker가 필요하다.
- 백엔드를 클러스터에 올릴 때(운영 구성) 아래를 함께 정하고 `infra/`에 절차로 남긴다. 개발 DB(Docker Desktop)로는 검증되지 않는 것들이다.
  - 스토리지: kubeadm 클러스터에는 기본 StorageClass가 없다. DB용 PersistentVolume을 준비하고, SSD 위에 둔다(HDD는 fsync가 느려 [ADR 008](008-개발-VM-실행-환경.md)에서 etcd가 멈췄다).
  - 격리: 같은 클러스터에서 학습자가 셸을 가진 실습 Pod가 돈다. NetworkPolicy로 실습 namespace에서 플랫폼 DB로 가는 길을 막는다.
  - 백업: 노드가 하나라 정기 덤프를 클러스터 밖에 둔다.
  - 재시작·메이저 버전 업그레이드 절차
