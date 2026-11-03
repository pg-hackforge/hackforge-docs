# hackforge-docs

Hackforge(웹 보안 공격·방어 실습 플랫폼)의 기획·결정·기능 스펙 저장소다. 코드는 없다.

## 저장소 3개 (`code/` 아래 나란히 클론)

- `../hackforge-docs`: 이 저장소. 무엇을, 왜 만드는지
- `../hackforge-be`: Spring Boot 백엔드. API 계약은 `../hackforge-be/openapi.yaml`
- `../hackforge-fe`: 프론트엔드 (스택 미정)
- Challenge는 문제마다 비공개 저장소 `hackforge-challenge-<문제>`에 둔다(decisions/007)

## 규칙

- 결정은 사람이 한다. AI는 초안을 쓰고, 정해지지 않은 것은 `미정 — 결정 필요:` 줄로 질문을 남긴다. 요구사항이나 결정을 임의로 채우지 않는다.
- `product.md`가 최상위 기준이다. 코드와 어긋나면 문서를 먼저 고친다.
- `decisions/`는 추가만 한다. 결정이 바뀌면 새 ADR을 쓰고, 예전 ADR은 상태 줄만 `대체됨 (NNN)`으로 바꾼다.
- 기능 스펙은 큰 기능만 `specs/<기능>/tasks.md` 하나로 쓴다(MVP 규모). 오타·문구·이름 변경에는 쓰지 않는다.
- `specs/` 아래 폴더 이름은 영어 소문자 kebab-case로 쓴다(예: `specs/account/`, `specs/lab-environment/`). 경로가 이슈·PR·명령에 자주 들어가서다. ADR 파일 이름은 지금처럼 한글을 쓴다.
- 끝난 기능의 스펙은 지우지 않는다.
- 클러스터·서버 구성 절차는 `infra/`에 둔다. 구성을 바꾸거나 새로 알게 된 함정이 있으면 같은 PR에서 절차 문서를 고친다. 특정 PC의 경로·IP·사양은 쓰지 않고 자리표시자로 둔다.

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
- PR 본문은 PR 템플릿 칸을 모두 채운다.
- 커밋 접두어: `feat:` `fix:` `docs:` `chore:`
- 커밋 본문은 diff로 알 수 없는 이유만 한두 줄 쓴다. 뻔한 변경은 제목 한 줄로 끝낸다.
- 라벨: `feature` `bug` `be` `fe` `infra`
- `suhodang/<이 저장소 이름>`은 `main`과 태그를 자동으로 덮어쓰는 읽기 전용 사본이다(`.github/workflows/mirror.yml`). 거기서 작업하지 않는다.
