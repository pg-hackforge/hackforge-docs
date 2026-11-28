# Hackforge 로드맵

- 기준: [product.md](product.md). 버전별로 무엇을 하는지와 문제 목록을 둔다. 계획이 바뀌면 이 문서를 고친다(ADR처럼 추가만 하는 문서가 아님)
- 결정 근거는 각 줄의 ADR과 이슈에 있다
- 미정(결정 필요): v1.1, v1.2 일정

## v1 (2026년 12월 초)

12월 초는 시연 날짜이고, 운영 서버 배포는 v1 뒤에 한다(2026-11-27 사람이 결정). 시연 전용 코드나 경로는 두지 않고 운영 기준으로 만든다.

계정, 문제 목록, 실습 환경, 공격 대상과 웹 터미널, 공격 검증과 힌트, 방어 IDE와 재배포, 방어 검증과 해답, 관리와 기록, fe 화면 전체, 소개 화면은 끝났다. 마지막으로 한 아래 세 가지도 끝나서(2026-11-28) v1에 남은 작업은 없다.

1. 문제 상태(예정, 공개)와 분류 추가: [ADR 031](decisions/031-문제-상태와-버전.md) v1, [ADR 032](decisions/032-분류-추가.md), [specs/more-challenges](specs/more-challenges/tasks.md) 작업 1~5
2. 문제 2 `idor-memo`, 문제 3 `cmdi-ping`과 개발 VM 측정: specs/more-challenges 작업 6~8, [운영 runbook](infra/lab-operations.md) 7절
3. hackforge-be #60(exec가 가끔 연결 오류로 끝남) 원인 조사와 수정: hackforge-be #75. READY와는 상관없었고, 검증 스크립트 끝에 붙이던 `exit`가 원인이었다([운영 runbook](infra/lab-operations.md) known issues)

## v1.1

- 배포 준비(v1에서 옮김, 2026-11-27 사람이 결정). 미정(결정 필요): 운영 서버 사양, 학교 규칙, 공유기 NAT와 hairpin NAT, 운영 시작 날짜, 백엔드와 DB를 클러스터 안에 둘지, reverse proxy, 노드 이미지 import, 배포 방법, DB 백업, 첫 관리자 계정
- 이용약관과 개인정보 처리방침(배포 준비에 포함, 2026-11-27 사람이 결정). 실제 사용자를 받기 전에 필요하고 관리자 열람과 수락 뒤 조작(ADR 033)을 고지함
- 백엔드가 꺼진 배포 중 점검 화면(reverse proxy 고정 페이지, ADR 034)
- hackforge-docs #94 실습 세션 운영 관리(일괄 종료, 종료 안내, 관리자 세션 보기와 학습자 수락 뒤 조작): [ADR 033](decisions/033-실습-세션-운영-관리.md), [specs/lab-admin](specs/lab-admin/tasks.md). v1에서 옮김(2026-11-27 사람이 결정)
- hackforge-docs #95 공지와 점검 안내: [ADR 034](decisions/034-공지와-점검.md), [specs/notices](specs/notices/tasks.md). 점검 자동 종료가 #94의 일괄 종료를 씀. v1에서 옮김(2026-11-27 사람이 결정)
- hackforge-docs #74 운영 HTTPS와 도메인
- hackforge-docs #18 이메일 인증과 비밀번호 재설정. 메일 발송에 도메인이 필요해 #74 도메인 뒤에 한다(2026-11-27 사람이 결정). 미정(결정 필요): 발송 서비스(추천은 Resend, 백엔드는 표준 SMTP로 보냄), 발송 대기열(outbox)과 반송 웹훅을 넣을지
- hackforge-docs #60 계정 정지
- hackforge-docs #61 본인 탈퇴
- 학습자 로컬에서 접속하는 HTTPS tunnel CLI([ADR 004](decisions/004-로컬-연결-방식.md))
- 관리자 세션 하나 조회 API `GET /api/admin/labs/{id}`(주소로 바로 연 오래된 세션의 학습자 표시, 2026-11-25 사람이 결정)

## v1.2

- hackforge-docs #19 GitHub·Google 로그인
- 문제 버전과 심사, 출제: [ADR 031](decisions/031-문제-상태와-버전.md) A(문제·버전 분리, 두 상태, 상태 기록), B(관리자 문제 탭과 심사), C(제출 때 자동 검사), D(출제자 화면과 권한)
- 문제마다 여러 언어로 구현: ADR 031과 함께 설계. 미정(결정 필요): 구현을 v1.2에 할지 그 뒤에 할지

## 그 뒤

- 나중에 하기로 한 운영 기능: 학습자에게 메시지 보내기(ADR 033), 공지 읽음 표시, 점검 기록 공개 페이지, SSE, 공지 고친 내용 전체 이력, 점검 예고 메일(#18 뒤, ADR 034)
- 30명 규모 운영(multi node, 생성 대기열, 백엔드 다중 인스턴스, 부하 테스트). 지금은 설계만 함
- 문제 등록 파이프라인(CI 빌드·SBOM·취약점 스캔 → registry). 방향(2026-11-27 사람이 정함): 출제자는 template을 fork해 개발하고 저장소 링크로 제출한다. 서버가 제출 시점 commit을 가져와 `meta/` 형식을 검사하고, 격리된 환경에서 빌드·스캔·`check.sh`를 돌린 뒤 문제 버전으로 넣어 ADR 031 B·D 심사로 넘긴다. 미정(결정 필요): 비공개 저장소 접근 방식, 빌드 격리 방식, v1.2에 넣을지. v1은 관리자가 `register.sh`로 등록한다

## 문제 목록

언어는 첫 구현의 언어다. 예정 문제는 목록에 "(예정)"으로 보이고 실습은 시작할 수 없다(ADR 031). 문제를 더하거나 바꾸면 이 표를 먼저 고치고, 예정 문제는 backend migration PR로 넣는다.

| 분류 | slug | 제목 | 언어 | 난이도 | 상태 |
|---|---|---|---|---|---|
| SQL Injection | `sqli-login` | SQL Injection 로그인 우회 | PHP | 입문 | 공개 |
| 접근 제어 | `idor-memo` | 남의 비공개 메모 열람 | Node.js | 초급 | v1에서 만듦 |
| Command Injection | `cmdi-ping` | 네트워크 진단으로 명령 실행 | Python | 초급 | v1에서 만듦 |
| 정보 노출 | `info-backup` | 남겨진 백업 파일과 디버그 페이지 | Node.js | 입문 | 예정 |
| Path Traversal | `path-download` | 파일 다운로드 경로 조작 | Go | 입문 | 예정 |
| XSS | `xss-search` | 검색어가 그대로 출력되는 반사형 XSS | PHP | 입문 | 예정 |
| XSS | `xss-board` | 게시판 저장형 XSS로 관리자 세션 탈취 | Python | 초급 | 예정 |
| 인증·세션 | `auth-reset` | 비밀번호 재설정 토큰 추측 | Java | 초급 | 예정 |
| 접근 제어 | `access-role` | 회원 정보 수정 요청에 role을 끼워 관리자 되기 | Python | 초급 | 예정 |
| 파일 업로드 | `upload-profile` | 프로필 사진 업로드로 웹셸 올리기 | PHP | 초급 | 예정 |
| CSRF | `csrf-transfer` | 포인트 송금 요청 위조 | Node.js | 초급 | 예정 |
| SQL Injection | `sqli-search` | 검색창 UNION으로 다른 테이블 읽기 | Java | 중급 | 예정 |
| 인증·세션 | `auth-jwt` | 약한 서명 키로 JWT 위조 | Node.js | 중급 | 예정 |
| 파일 업로드 | `upload-ext` | 확장자 검사 우회 | Java | 중급 | 예정 |
| SSRF | `ssrf-preview` | 링크 미리보기로 내부 관리 API 호출 | Go | 중급 | 예정 |
| XXE | `xxe-import` | XML 가져오기로 서버 파일 읽기 | Java | 중급 | 예정 |
| SQL Injection | `sqli-blind` | 참·거짓 응답 차이로 비밀번호 알아내기 | Go | 고급 | 예정 |
| SSRF | `ssrf-redirect` | 리다이렉트로 내부 주소 필터 우회 | PHP | 고급 | 예정 |
| 역직렬화 | `deser-cookie` | 직렬화된 쿠키로 코드 실행 | Python | 고급 | 예정 |

- 예정 문제의 요약과 예상 시간은 migration PR에서 정한다. `idor-memo`와 `cmdi-ping`도 migration에는 예정으로 넣고 등록할 때 공개된다
- XSS와 CSRF 문제는 피해자 역할의 브라우저 봇이 Pod 안에 있어야 한다. headless 브라우저 크기 때문에 `images.tar` 450MB 상한에 걸릴 수 있어 만들 때 따로 확인한다
- 새 분류 다섯(SSTI, NoSQL Injection, 비즈니스 로직, 보안 설정 오류, Prototype Pollution, [ADR 032](decisions/032-분류-추가.md))에는 아직 문제가 없다
