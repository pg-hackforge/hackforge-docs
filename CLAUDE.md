# hackforge-docs

Hackforge(웹 보안 공격·방어 실습 플랫폼)의 기획·결정·기능 스펙 저장소다. 코드는 없다.

## 저장소 3개 (`code/` 아래 나란히 클론)

- `../hackforge-docs`: 이 저장소. 무엇을, 왜 만드는지
- `../hackforge-be`: Spring Boot 백엔드. API 계약은 `../hackforge-be/openapi.yaml`
- `../hackforge-fe`: 프론트엔드 (스택 미정)

## 규칙

- 결정은 사람이 한다. AI는 초안을 쓰고, 정해지지 않은 것은 `미정 — 결정 필요:` 줄로 질문을 남긴다. 요구사항이나 결정을 임의로 채우지 않는다.
- `product.md`가 최상위 기준이다. 코드와 어긋나면 문서를 먼저 고친다.
- `decisions/`는 추가만 한다. 결정이 바뀌면 새 ADR을 쓰고, 예전 ADR은 상태 줄만 `대체됨 (NNN)`으로 바꾼다.
- 기능 스펙은 큰 기능만 `specs/<기능>/tasks.md` 하나로 쓴다(MVP 규모). 오타·문구·이름 변경에는 쓰지 않는다.
- 끝난 기능의 스펙은 지우지 않는다.

## tasks.md 형식

````markdown
# <기능> 작업 목록

관련 이슈: #N · 결정: decisions/NNN (있으면)

## 완료 기준
- ...

## 예외 상황
- ...

## 작업
- [ ] 1. [be] ... — 테스트: ...
- [ ] 2. [fe] ... — 테스트: ...
````

- 작업 하나는 PR 하나로 리뷰할 수 있는 크기로 쪼갠다.
- API가 바뀌면 첫 작업은 `[be] openapi.yaml 수정`이다.

## ADR 형식 (`decisions/NNN-제목.md`)

````markdown
# NNN. 제목

- 상태: 제안 | 채택 | 대체됨 (NNN)
- 날짜: YYYY-MM-DD

## 배경
## 선택지
## 결정
## 이유
## 결과
````

## Git

- GitHub Flow를 쓴다. `main`에서 짧은 브랜치(`docs/...`)를 따고 PR로 머지한다. `main`에 직접 push하지 않는다.
- 커밋 접두어: `feat:` `fix:` `docs:` `chore:`
- 커밋 본문은 diff로 알 수 없는 이유만 한두 줄 쓴다. 뻔한 변경은 제목 한 줄로 끝낸다.
- 라벨: `feature` `bug` `be` `fe`
