# 문제 추가 작업 목록

관련 이슈: 없음(작업 목록만으로 진행, 2026-11-26 사람이 결정) · 결정: [decisions/031](../../decisions/031-문제-상태와-버전.md)(v1 부분), [decisions/032](../../decisions/032-분류-추가.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md), [decisions/020](../../decisions/020-문제-정보와-목록-API.md)

v1에 문제 2·3을 더하고, 앞으로 만들 문제를 목록에 "(예정)"으로 미리 보인다. 문제 목록은 [roadmap.md](../../roadmap.md) "문제 목록"에 있다.

## 완료 기준

- 분류가 17개(ADR 032)
- 예정 문제가 목록에 "(예정)"으로 공개 문제 뒤에 보이고, 상세에는 요약과 "준비 중이에요"가 보임
- 예정 문제는 실습을 시작할 수 없고(API 409), 새 문제 표시, 홈 추천, 내 기록 분석 추천, 진행 요약에 들어가지 않음. 필터 개수에는 들어감(ADR 031 정정)
- 새 문제 표시와 새로 추가된 순은 공개 시각(`published_at`) 기준
- `idor-memo`(Node.js), `cmdi-ping`(Python)이 예정에서 공개로 바뀌고, 개발 VM에서 공격 검증과 방어 검증이 해답대로 통과함
- 두 문제 모두 실습 Pod 메모리 512Mi, 디스크 2Gi 안에서 동작하고 `images.tar`가 450MB 이하

## 예외 상황

- 예정 문제 실습 시작 요청: 409, 세션을 만들지 않음
- 예정 문제와 같은 slug로 `register.sh`: 내용을 채우고 공개로 바꾸며 `published_at`을 그때로 채움
- 공개 문제를 다시 등록: `published_at`은 처음 값 그대로
- 공개 문제의 이미지·설명·스크립트·해답이 비면 DB 제약이 거절하고 등록 transaction 전체가 취소됨
- 진행 중 세션이 있는 문제는 다시 등록하지 않음(운영 runbook 4절)

## 작업

- [x] 1. [docs] 이 작업 목록, roadmap.md, ADR 032, 운영 runbook의 재등록 규칙과 디스크 기준 (확인: ADR 031·032와 맞음)
- [x] 2. [be] openapi.yaml 수정: 문제 목록·상세의 `status`, 예정 문제 시작 409 오류 코드 (테스트: openapi lint)
- [x] 3. [be] migration과 구현: `challenges.status`·`published_at`, 공개 문제만 필수인 칸의 DB 제약, 분류 5개, 예정 문제 18개(문제 2·3 포함, 요약과 예상 시간은 PR에서 정함), 시작 거절, 새 문제·진행 요약에서 제외(필터 개수에는 포함), 예정 문제는 공개 문제 뒤 (테스트: 목록·개수·정렬·시작 거절 통합 테스트, 개발 DB에 migration 적용)
- [x] 4. [challenge] template과 `sqli-login`의 `register.sh`: 공개로 바꾸고 처음 공개할 때 `published_at` (확인: 개발 DB에서 예정 → 공개, 다시 등록해도 `published_at` 유지)
- [x] 5. [fe] 목록·상세의 "(예정)"과 "준비 중이에요", 홈 추천과 내 기록 분석 추천에서 예정 문제 제외, mock에 예정 문제 (테스트: 단위 테스트, mock과 개발 백엔드 캡처)
- [x] 6. [challenge] `idor-memo`: Node.js 24 + Express, 내장 SQLite, 메모 보기 화면과 API 두 경로의 IDOR, 공유 메모 함정, 힌트, 해답 (확인: `check.sh`, 원본에서 공격 통함, 해답 적용 뒤 막힘과 정상 기능)
- [ ] 7. [challenge] `cmdi-ping`: Python 3.13 + Flask, 셸 문자열로 ping 실행, `;`·`&`만 막는 필터 함정, 힌트, 해답 (확인: 작업 6과 같음)
- [ ] 8. [docs] 개발 VM 등록과 측정(준비 시간, 메모리, 디스크, 검증 스크립트 결과)을 운영 runbook에 (확인: 백엔드 API로 실제 세션)
