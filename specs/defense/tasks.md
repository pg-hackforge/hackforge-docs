# 방어: 웹 IDE, 재빌드·재배포, 초기화 작업 목록

관련 이슈: #10 · 결정: [decisions/024](../../decisions/024-방어-IDE-재배포-초기화.md), [decisions/022](../../decisions/022-공격-대상과-웹-터미널-연결.md), [decisions/023](../../decisions/023-공격-검증과-힌트.md), [decisions/016](../../decisions/016-fe-디자인-방향.md), [decisions/014](../../decisions/014-challenge-형식과-등록.md)

방어 단계에서 학습자가 웹 IDE로 코드를 고치고 재배포한다. 망가뜨리면 서비스 초기화나 실습 환경 다시 만들기로 되돌린다. 방어 힌트를 공개한다. 이 목록은 Challenge 저장소와 백엔드까지이고, fe 실습 화면은 백엔드가 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- Challenge 이미지에 원본 코드 사본(`/hackforge/original`)이 있고, 문제마다 수정 불가 파일(`READONLY`)을 정해 등록
- 방어 단계에서 `/app` 파일 목록, 읽기(SHA-256), 저장(해시 확인), 원본으로 되돌리기. 수정 불가 파일은 저장·되돌리기 거절
- 재배포를 요청하면 비동기로 `docker compose build`·`up -d`·healthy 대기를 하고 성공·실패와 빌드 로그(끝 64KB)를 기록
- 서비스 초기화(원본 복원, `down -v`, 다시 기동)와 실습 환경 다시 만들기(Pod 재생성), "현재 단계 유지"와 "처음부터"
- 세션마다 검증·재배포·서비스 초기화 중 하나만 실행
- 방어 힌트를 1 → 2 → 3 순서로 공개하고 공개 시각 기록
- 파일 저장·되돌리기, 재배포, 초기화, 방어 힌트 요청이 활동으로 기록됨

## 예외 상황

- 세션이 `READY`가 아님: 409 `LAB_NOT_READY`
- 공격 단계에서 파일 API, 재배포, 방어 힌트: 409 `WRONG_LAB_STAGE`
- 수정 불가 파일 저장·되돌리기: 403
- 저장 때 해시가 다름(터미널에서 바뀜): 409, 화면이 다시 읽을지 물음
- 1MB 초과나 바이너리 파일 열기: 거절(목록에는 보임)
- `/app` 밖 경로(`..` 포함): 400
- 검증·재배포·초기화 중 하나가 실행 중: 409
- 빌드 실패나 3분 안에 healthy가 안 됨: `FAIL`, 빌드 로그 표시, 초기화 안내
- exec 실패: `ERROR`, 다시 시도 안내. 서비스 초기화가 실패하면 실습 환경 다시 만들기 안내
- 실행 중 백엔드 재시작: 백엔드가 시작할 때 남은 `RUNNING`(검증, 재배포, 초기화)을 모두 `ERROR`로. 안전망으로 reconciler가 4분(검증은 2분) 지난 `RUNNING`을 `ERROR`로
- 실습 환경 다시 만들기 중: 터미널은 닫히고 공격 대상은 준비 중 안내, 준비 단계가 다시 보임

## 작업

- [x] 1. [docs] ADR 024, 이 작업 목록, `data-model.md`(`challenges.readonly_paths`, `redeploys`), product.md 유스케이스 7 (확인: 사람이 정한 결정과 맞음)
- [x] 2. [be] `openapi.yaml` 0.7.0: 파일 목록·읽기·저장·되돌리기, 재배포 요청·조회·목록, 초기화, 방어 힌트, 세션 응답, 오류 코드 (테스트: OpenAPI lint)
- [x] 3. [challenge] `hackforge-challenge-template`: Dockerfile `COPY app/ /hackforge/original/`, `challenge.env` `READONLY`, `register.sh` 저장, README. `hackforge-challenge-sqli` 같은 변경과 다시 빌드. 테스트 문제(`infra/lab-test-challenge`) 원본 사본. 개발 클러스터 import와 개발 DB 등록 (확인: Pod 안 `/hackforge/original`에 원본, 등록된 `readonly_paths`)
- [x] 4. [be] migration V11, 파일 API(exec, base64, 해시, 수정 불가, 경로 확인) (테스트: 가짜 클러스터로 목록·읽기·저장·되돌리기, 해시 충돌 409, 수정 불가 403, 경로 400, 크기·바이너리, 단계·상태 409, 활동)
- [x] 5. [be] 재배포와 서비스 초기화 실행(비동기, 로그, 시작할 때와 시간 기준 복구. 검증에도 시작할 때 복구), 실습 환경 다시 만들기, 처음부터, 동시 실행 제한, 방어 힌트 (테스트: 성공·실패·시간 초과·exec 실패, 로그 64KB, 검증과 재배포 동시 409, 다시 만들기 뒤 `CREATING`, 처음부터의 단계, 방어 힌트 순서)
- [x] 6. [be] clusterTest: 개발 클러스터의 실제 Pod에서 파일을 고치고 재배포해 응답이 바뀌고, 서비스 초기화로 원본과 초기 DB로, 실습 환경 다시 만들기로 READY까지 (테스트: `./gradlew clusterTest`)
