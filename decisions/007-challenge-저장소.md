# 007. Challenge 저장소: 문제마다 private repo

- 상태: 채택
- 날짜: 2026-11-02

## 배경

Challenge 하나에는 Compose 프로젝트, 공격 검증 규칙, 정상 기능 테스트, 힌트 3개, 해답, 방어 검증 최대 시도 횟수가 들어간다. 출제자는 플랫폼 화면이 아니라 저장소에 직접 추가하고, v1 문제는 2~3개이며 이미지는 수동으로 빌드한다. 등록 파이프라인(CI 빌드, SBOM, 취약점 스캔, registry)은 v1 이후에 넣는다.

[ADR 003](003-저장소-분리.md)의 저장소 셋(docs, be, fe)에는 Challenge를 둘 곳이 정해져 있지 않다.

## 선택지

1. 문제마다 저장소: `hackforge-challenge-<문제>`
2. 저장소 하나(`hackforge-challenges`)에 문제마다 폴더

## 결정

1번을 택한다.

- 저장소 이름: `hackforge-challenge-<문제>` (예: `hackforge-challenge-sqli`)
- 전부 private
- template repo `hackforge-challenge-template`을 GitHub Template repository로 두고, 새 문제는 여기서 생성
- 저장소 안은 두 부분으로 나눔
  - `app/`: 학습자 환경에 복사되는 부분. 취약한 앱 코드와 Compose
  - `meta/`: 플랫폼만 읽는 부분. 해답, 힌트, 공격 검증 규칙, 정상 기능 테스트, 최대 시도 횟수. 학습자 환경에 넣지 않음

## 이유

- 문제 하나가 파이프라인 하나, 이미지 하나와 맞음. 저장소 tag를 이미지 tag로 바로 쓸 수 있음(예: `ghcr.io/pg-hackforge/challenge-sqli:v1.0.0`). 2번은 바뀐 폴더만 골라 빌드하는 필터와 tag에서 문제 이름을 잘라 내는 처리가 필요함
- 한 문제의 CI가 깨져도 다른 문제에 영향 없음
- 저장소마다 설정이 중복되는 비용은 template repo로 줄임
- 해답과 검증 규칙이 들어 있어 공개하면 학습자가 정답을 보게 됨

## 결과

- private repo라 GitHub Free 플랜에서는 `main` Ruleset을 걸 수 없다. 출제자가 혼자인 동안은 감수하고, 출제자가 늘면 Team 플랜을 검토한다.
- 형식이 바뀌면 문제 수만큼 PR이 필요하다. 문제가 많아지면 CI를 reusable workflow(`workflow_call`)로 모은다.
- template repo와 첫 문제 저장소는 Challenge 형식을 정하는 작업(#7)에서 만든다.
- v1 template CI는 빌드와 테스트까지만 하고, registry push는 등록 파이프라인을 넣을 때 추가한다.
- 플랫폼이 문제 목록을 알려면 Challenge 저장소나 이미지 목록이 필요하다. 방식은 #7에서 정한다.
