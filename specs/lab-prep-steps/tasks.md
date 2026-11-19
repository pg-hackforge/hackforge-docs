# 실습 환경 준비 단계 작업 목록

관련 이슈: #66 · 결정: [decisions/021](../../decisions/021-실습-환경-준비-단계.md), [decisions/012](../../decisions/012-실습-환경-수명-주기.md), [decisions/013](../../decisions/013-실습-pod-격리와-백엔드-권한.md), [decisions/016](../../decisions/016-fe-디자인-방향.md)

실습 환경을 준비하는 동안 지금 어느 단계인지 학습자에게 보여 줄 수 있게 한다. reconciler가 준비 중인 세션의 Pod 로그에서 시작 스크립트의 단계 기록을 읽어 DB에 저장하고, 실습 세션 응답에 넣는다. fe 실습 시작 화면은 이 작업이 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- 준비 단계 4개(`SPACE`, `CONTAINER`, `LOADING`, `STARTING`)와 판정 기준을 ADR 021로 남김
- reconciler가 `INITIALIZING` 세션의 Pod 로그에서 단계 기록(`dockerd-ready`, `images-loaded`)을 읽어 `lab_sessions.prep_step`에 저장
- `LabSessionResponse`에 `prepStep`(준비 중이 아니면 `null`)과 `retrying`
- 백엔드 service account에 `pods/log` `get`을 더하고 개발 클러스터에 적용
- 개발 클러스터의 실제 Pod에서 단계가 `SPACE`, `CONTAINER`, `LOADING`, `STARTING` 순서로 바뀌고 Ready가 되면 `null`

## 예외 상황

- Pod 로그 읽기 실패(권한, API server 오류, Pod가 아직 시작 전): 이전 단계 유지, 다음 주기에 다시 읽음. Ready 판정과 실패 처리는 지금과 같음
- 로그에 단계 기록이 없음(오래된 이미지, 아직 출력 전): `CONTAINER` 유지
- 이미 지난 단계보다 앞 단계로 보이는 로그: 단계를 되돌리지 않음
- 재시도: `CREATING`으로 돌아가면서 `SPACE`, `retrying`은 `true`
- 준비 중 종료 요청: `TERMINATING`이 되면서 `prep_step`은 `null`
- 학습자가 Pod 안에서 가짜 단계 기록을 출력: 자기 화면의 단계 표시만 바뀜. 준비 완료는 readinessProbe가 판정

## 작업

- [ ] 1. [docs] ADR 021(준비 단계, 판정, 저장, API, 권한), 이 작업 목록, `data-model.md`(`lab_sessions.prep_step`) (확인: 사람이 정한 결정과 맞음)
- [ ] 2. [be] `openapi.yaml` 0.4.0: `LabPrepStep`, `LabSessionResponse`의 `prepStep`, `retrying` (테스트: OpenAPI lint)
- [ ] 3. [infra] `infra/k8s/hackforge-backend.yaml`에 `pods/log` `get`, `infra/cluster-setup.md` 8.2 설명, 개발 클러스터에 적용 (확인: 백엔드 kubeconfig로 `kubectl auth can-i get pods/log -n lab-1`이 `yes`, `delete pods/log`는 `no`)
- [ ] 4. [be] migration V9 `prep_step`, `LabCluster`에 Pod 로그 읽기, reconciler 단계 판정과 저장, 응답 필드 (테스트: 가짜 클러스터로 단계 기록마다 단계 전이, 로그 읽기 실패와 기록 없음에서 단계 유지, 앞 단계 로그에서 되돌리지 않음, 재시도 시 `SPACE`와 `retrying`, Ready·종료 시 `null`, 응답 필드)
- [ ] 5. [be] clusterTest: 개발 클러스터에서 테스트 문제 세션을 시작해 단계가 순서대로 바뀌고 Ready에서 `null`이 되는지 확인 (테스트: `./gradlew clusterTest`)
