# fe 초기 구성 작업 목록

관련 이슈: #45 · 결정: [decisions/015](../../decisions/015-fe-스택.md), [decisions/016](../../decisions/016-fe-디자인-방향.md)

hackforge-fe에 스택, 개발 환경, API 연결, mock 모드, 앱 틀을 만든다. 실제 화면(계정, 문제 목록, 실습)은 기능별 별도 이슈에서 만들고, 디자인 방향(배치, 색, 테마)은 [decisions/016](../../decisions/016-fe-디자인-방향.md)에서 정했고, 작업 6에서 색 토큰과 `DESIGN.md`로 옮긴다. fe PR은 확인할 화면 목록과 실행 방법을 적고, 리뷰는 직접 띄워서 화면으로 한다.

## 완료 기준

- `npm run dev`로 띄운 fe가 Vite proxy로 개발 백엔드(`127.0.0.1:8080`)에 붙어 로그인 상태(`GET /api/me`)를 읽음. 백엔드 설정 변경 없이 cookie, CSRF 동작
- `npm run dev:mock`으로 백엔드 없이 fe만 띄워 시나리오별 상태 확인
- `npm run api:sync`로 `openapi.yaml` 복사본과 생성물 갱신. CI가 생성물과 복사본 일치 확인
- 앱 틀: 레이아웃, 라이트·다크 테마, 로그인 필요 구간과 관리자 구간, 404·403 화면
- CI: 타입 검사, lint, 테스트, 빌드

## 예외 상황

- 백엔드가 꺼진 상태에서 `npm run dev`: 연결 실패 안내와 `dev:mock` 안내를 표시
- `openapi.yaml`이 바뀌었는데 sync하지 않음: 오래된 타입으로 동작, `api:sync` 뒤 컴파일 오류로 드러남
- 데이터를 바꾸는 요청에 `XSRF-TOKEN` cookie가 없음: `GET /api/me`로 먼저 받고 보냄
- 로그인 필요 구간에서 401: 로그인 화면으로 이동. 로그인 화면 자체는 계정 화면 이슈에서 만들고, 여기서는 자리만 둠
- 관리자가 아닌 사용자가 관리자 경로로 들어옴: 403 화면. 최종 권한 확인은 백엔드
- 미정(결정 필요): 운영에서 fe 정적 파일을 어디서 서빙할지. 운영 서버 구성 때 정함(ADR 015)

## 작업

- [x] 1. [docs] ADR 015(fe 스택), 이 작업 목록, product.md 기술 스택 표, docs `CLAUDE.md` 저장소 설명 (확인: 사람이 정한 결정과 맞음)
- [x] 2. [fe] 프로젝트 뼈대: Vite + React + TypeScript(strict), Tailwind CSS v4, shadcn/ui 초기화, Pretendard, 라이트·다크 테마 전환, ESLint·Prettier, Vitest, `.nvmrc`(Node 26), CI(타입 검사, lint, 테스트, 빌드), fe `CLAUDE.md`·README에 실행·테스트 명령 (확인: `npm run dev`로 빈 시작 화면이 라이트·다크로 보임, CI 통과)
- [ ] 3. [fe] API 연결: `api:sync`(복사와 생성), hey-api 설정(SDK, TanStack Query), client(같은 주소, CSRF interceptor, 401 처리, Problem `code`와 `errors[]` 변환), Vite proxy, CI 생성물 일치 확인 (테스트: 데이터를 바꾸는 요청에 `X-XSRF-TOKEN`이 붙음, cookie가 없으면 먼저 받음, `VALIDATION_FAILED`가 필드별 오류로 변환됨, 401이 로그아웃 상태로 처리됨. 확인: 개발 백엔드에서 `GET /api/me` 결과가 화면에 보임)
- [ ] 4. [fe] mock 모드: MSW, 생성 타입에 맞춘 handler, 시나리오 전환(로그인 안 됨, 승인 대기, 학습자, 관리자, 실습 CREATING·READY·FAILED·정원 초과), `dev:mock` (확인: 백엔드 없이 시나리오를 바꾸면 화면 상태가 바뀜)
- [ ] 5. [fe] 앱 틀: 레이아웃(상단바, 사용자 메뉴, 테마 전환), React Router, 로그인 필요 구간과 관리자 구간, 승인 대기 안내 띠, 404·403·백엔드 연결 실패 화면 (확인: mock 시나리오별로 메뉴와 접근이 바뀜, 화면 목록을 PR에 적음)
- [ ] 6. [fe] 디자인 토큰과 `DESIGN.md`: 흑연과 불씨 색 토큰(라이트·다크)을 `src/index.css`에, 색·글꼴·배치·컴포넌트 규칙을 `DESIGN.md`에, 제품 맥락을 `PRODUCT.md`에 (확인: 시작 화면이 라이트·다크에서 확정 색으로 보임, `DESIGN.md`의 값과 `src/index.css`의 값이 같음)
