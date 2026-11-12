# 실습 환경 작업 목록

관련 이슈: #6 · 결정: [decisions/012](../../decisions/012-실습-환경-수명-주기.md), [decisions/013](../../decisions/013-실습-pod-격리와-백엔드-권한.md)

실습 시작과 종료, 생성 실패 재시도, idle 종료까지 다룬다. 공격 대상 화면과 웹 터미널은 #8, Challenge 형식과 첫 문제(SQLi)는 #7에서 하고, 여기서는 테스트 문제(nginx + PostgreSQL) 하나로 확인한다. `challenges` 테이블은 `lab_sessions`가 FK로 참조해서 여기서 만들고, 문제 목록 API(`GET /api/challenges`, spec은 hackforge-be#23)와 문제 등록 방식은 #7에서 구현한다. 화면(fe)은 스택을 정한 뒤 별도 이슈로 만들고, 이 목록은 백엔드 API, 클러스터 구성, 테스트까지만 다룬다.

## 완료 기준

- 승인된 학습자가 문제를 골라 시작하면 세션이 `CREATING`으로 생기고, 전용 namespace와 Pod가 만들어져 `READY`가 됨 (유스케이스 2)
- 학습자가 종료하면 namespace가 삭제되고 세션이 `DELETED`가 됨 (유스케이스 8)
- 학습자당 진행 중인 세션은 1개. DB partial unique index로 보장
- 동시 세션 수는 `hackforge.lab.max-concurrent` 이하. `TERMINATING`도 삭제가 끝날 때까지 포함
- 마지막 활동 후 `hackforge.lab.idle-timeout`(30분)이 지나면 세션이 `IDLE`로 종료되고 환경이 삭제됨. 응답의 `idleWarningAt`(종료 5분 전)부터 fe가 경고를 띄울 수 있고, [계속하기](`/activity`)를 보내면 기한이 다시 늘어남
- idle 판단 입력은 #6에서는 `/activity` 하나. 웹 터미널, Target으로 가는 요청(#8), 웹 IDE(#10)는 같은 기록 경로를 호출하도록 그 이슈에서 연결함
- 실습 Pod에서 인터넷, API server, kubelet, 다른 세션, 노드 IP로 연결되지 않음
- 실습 Pod에는 API token이 없고, CPU, 메모리, 프로세스 수, 디스크 상한이 걸림
- 백엔드는 `lab-` namespace 밖의 오브젝트를 만들거나 지울 수 없음
- client-java의 transitive dependency(Jackson, Bouncy Castle) 취약점 확인, 필요하면 버전 pin (ADR 001)

## 예외 상황

- 승인 대기나 거절 계정이 시작: 403 `ACCOUNT_NOT_APPROVED`, 승인 대기 중 안내. 승인 상태는 매번 DB에서 읽음
- 진행 중이거나 종료 중인 세션이 있는데 시작: 409 `LAB_ALREADY_ACTIVE`, fe는 기존 세션으로 안내
- 동시 정원 초과: 503 `LAB_CAPACITY_FULL`, "지금은 자리가 없습니다". 대기열 없음
- 없는 문제: 404 `CHALLENGE_NOT_FOUND`
- 없거나 남의 세션 조회·종료: 404 `LAB_NOT_FOUND`
- `READY`가 아닌 세션에 [계속하기]: 409 `LAB_NOT_READY`
- 환경 생성 실패(Pod `Failed`, image pull 실패) 또는 `start-timeout` 초과: Pod만 지우고 1회 재시도. 두 번째도 실패하면 namespace를 지운 뒤 `FAILED`, fe는 "환경을 만들지 못했습니다"와 다시 시작 버튼
- `READY` 중 Pod가 죽거나(메모리 초과, 디스크 초과 eviction) 사라짐: `POD_LOST`로 종료
- 생성 중에 종료 요청: 종료함
- 이미 종료 중이거나 끝난 세션에 종료 요청: 그 상태를 그대로 응답
- 백엔드 재시작: DB 상태에서 이어서 진행. 요청은 DB에만 쓰고 클러스터는 reconciler만 호출함
- API server 연결 실패: 로그만 남기고 다음 주기에 재시도. 길어지면 생성 중인 세션은 `start-timeout`으로 실패 처리
- DB에 진행 중 세션이 없는 `lab-` namespace(탈퇴로 세션 행이 지워진 경우 등): orphan 정리가 삭제
- 개발 VM 설정값: CPU 500m, 메모리 512Mi, 디스크 2Gi, `max-concurrent` 2, `podPidsLimit` 4096, `start-timeout` 5m(2026-11-12 결정, 테스트 문제 Ready까지 21초)
- 미정(실측 후 결정): 운영 서버의 위 값. 운영 서버에서 확인 (ADR 006)
- 미정(결정 필요): 운영 서버에 Challenge 이미지를 넣는 방법. 운영 서버 구성 때 정함
- 백엔드 service account는 namespace `hackforge`에 둠(2026-11-12 결정, ADR 013)

## 작업

- [x] 1. [docs] ADR 012(수명 주기), ADR 013(격리와 백엔드 권한), 이 작업 목록, 엔티티 관계도(`data-model.md`) (확인: 사람이 정한 결정과 맞음, #32)
- [x] 2. [be] `openapi.yaml`에 `GET /api/challenges`, `POST /api/labs`, `GET /api/labs/current`, `GET /api/labs/{id}`, `DELETE /api/labs/{id}`, `POST /api/labs/{id}/activity`, 오류 코드 6개 추가 (테스트: OpenAPI lint, hackforge-be#23)
- [x] 3. [be] migration으로 `challenges`, `lab_sessions` 생성, 개발 전용 seed(`db/dev`, `bootRun`에서만). 같은 때 docs의 계정 운영 runbook에 `lab_sessions` 반영 (테스트: 진행 중 세션 2개 insert 시 unique 위반, 끝난 세션은 여러 개 가능, 사용자 삭제 시 세션 행 삭제, 세션 있는 문제 삭제 거절, 운영 설정에서는 seed가 적용되지 않음, hackforge-be#24, #33)
- [x] 4. [docs] `infra/`에 GlobalNetworkPolicy, 백엔드 service account와 RBAC, ValidatingAdmissionPolicy manifest, `cluster-setup.md`에 적용 단계와 kubelet `podPidsLimit` 추가, 개발 VM에 적용, 백엔드용 kubeconfig 만드는 절차 (확인: 백엔드 kubeconfig로 `lab-` namespace 생성·삭제는 되고 `kube-system` 조작은 거절됨, #34)
- [x] 5. [docs] `infra/lab-test-challenge/`에 테스트 문제 이미지(Dockerfile, `app/compose.yaml`, `hackforge/entrypoint.sh`, `hackforge/ready.sh`), 개발 VM에 import하는 절차. 시작 시간과 CPU, 메모리, 디스크 사용량을 재서 개발 설정값 결정 (확인: 개발 VM에서 Pod가 Ready가 되고 compose 서비스가 모두 healthy, 측정값 기록)
- [x] 6. [be] `LabCluster` 인터페이스와 client-java 구현, 테스트용 fake. client-java transitive dependency 확인. 실제 클러스터 테스트는 JUnit tag `cluster`로 `./gradlew build`에서 빼고 `./gradlew clusterTest`로 실행 (테스트: 개발 VM에서 namespace, NetworkPolicy, ResourceQuota, Pod 생성과 삭제, 같은 Pod를 다시 만들어도 1개 유지, `privileged` Pod 거절, `kube-system` 조작 거절, hackforge-be#25, hackforge-be#26)
- [x] 7. [be] 시작 API(승인 확인, advisory lock으로 정원 확인, 학습자당 1세션), `GET /api/labs/current`, `GET /api/labs/{id}` (테스트: 승인 대기·거절 403, 정원 초과 503, 같은 학습자 동시 시작 2건 중 1건만 성공, 정원 직전 여러 학습자 동시 시작 시 정원까지만 성공, 남의 세션 404, `current`가 없으면 204, hackforge-be#27)
- [x] 8. [be] `LabReconciler` 생성 흐름: `CREATING` → `INITIALIZING` → `READY`, 실패 시 재시도 1회와 `FAILED`, `READY` 중 Pod 유실 시 `POD_LOST`. `FAILED`와 `POD_LOST`가 namespace 삭제를 거치므로 `TERMINATING` 처리(namespace 삭제가 끝나면 `FAILED` 또는 `DELETED`)도 여기서 구현. reconciler가 읽은 뒤 다른 요청이 먼저 저장하면 reconciler 저장이 실패하도록 `@Version` 낙관적 잠금 (테스트: fake 클러스터와 주입한 `Clock`으로 각 전이, `start-timeout` 초과, 두 번째 실패 후 `FAILED`, 재시도 Pod가 세션의 `image`를 씀, 한 세션의 예외가 다른 세션 처리를 막지 않음, 읽은 뒤 바뀐 종료 요청이 유지됨, hackforge-be#29)
- [ ] 9. [be] 종료 API(`TERMINATING` 처리는 작업 8), orphan 정리 (테스트: 생성 중 종료, 종료 중 재요청은 같은 상태 응답, namespace 삭제가 끝나야 `DELETED`, 종료 중에는 새 시작이 409, DB에 없는 `lab-` namespace 삭제, `lab-`가 아닌 namespace는 건드리지 않음)
- [ ] 10. [be] idle 종료와 `POST /api/labs/{id}/activity`, 응답의 `idleDeadline`, `idleWarningAt` (테스트: 주입한 `Clock`으로 30분 경과 시 `IDLE` 종료, 경과 전 [계속하기]로 기한 연장, `READY`가 아니면 409, 생성 중에는 idle 시간을 세지 않음, 상태 조회는 활동으로 세지 않음)
- [ ] 11. [docs] 개발 VM에서 보안 확인을 하고 `infra/`에 실습 환경 운영 runbook 작성 (확인: 실습 Pod에서 인터넷, 6443, 10250, 다른 세션, 노드 IP 연결 실패, fork bomb이 Pod 안에서만 제한, 디스크를 채우면 해당 Pod만 eviction, 결과 기록)
