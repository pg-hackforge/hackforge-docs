# 공격 대상 화면과 웹 터미널 작업 목록

관련 이슈: #8 · 결정: [decisions/022](../../decisions/022-공격-대상과-웹-터미널-연결.md), [decisions/004](../../decisions/004-로컬-연결-방식.md), [decisions/012](../../decisions/012-실습-환경-수명-주기.md), [decisions/013](../../decisions/013-실습-pod-격리와-백엔드-권한.md), [decisions/016](../../decisions/016-fe-디자인-방향.md)

학습자가 브라우저로 자기 실습 Pod의 공격 대상 웹 화면과 터미널을 연다. 백엔드는 공격 대상을 port-forward로, 터미널을 exec로 연결하고, 공격 대상은 플랫폼과 다른 포트(origin)에서 연다. 이 목록은 백엔드와 인프라까지이고, fe 실습 화면(공격 대상 패널, 터미널)은 이 작업이 끝난 뒤 별도 이슈로 만든다.

## 완료 기준

- 공격 대상 포트로 들어온 요청이 로그인한 학습자의 `READY` 세션 Pod 안 `127.0.0.1:8080`으로 전달되고, 공격 대상 앱의 링크, 폼, cookie가 그대로 동작
- 플랫폼 cookie는 공격 대상 앱으로 넘어가지 않고, 공격 대상 앱은 플랫폼 cookie 이름으로 cookie를 심지 못하며, 실습이 바뀌면 이전 실습의 cookie가 지워짐
- 공격 대상 응답은 플랫폼 화면에서만 iframe으로 띄울 수 있음
- `/api/labs/{id}/terminal` WebSocket으로 실습 Pod의 `sh`(작업 폴더 `/app`)에 연결되고 입력, 출력, 크기 변경이 동작
- 다른 학습자의 세션, `READY`가 아닌 세션, 플랫폼이 아닌 `Origin`은 연결 거절
- 공격 대상 요청과 터미널 입력이 활동으로 기록되고 세션당 1분에 한 번만 DB에 씀
- 실습 Pod로 들어오는 네트워크 통신은 지금처럼 모두 막혀 있음

## 예외 상황

- 로그인하지 않았거나 `READY` 세션이 없음: 공격 대상 포트는 안내 페이지, 터미널은 연결 거절
- 공격 대상 앱이 응답하지 않음(서비스가 죽음, 30초 초과): 502, 504 안내 페이지. 세션 상태는 바꾸지 않음
- 공격 대상 앱이 `X-Frame-Options`, `frame-ancestors`로 iframe을 막음: `X-Frame-Options`는 지우고 플랫폼 origin만 허용. 앱의 CSP `frame-ancestors 'none'`은 그대로라 패널에 안 뜰 수 있음(새 탭으로 열기)
- port-forward 연결이 끊김: 다음 요청에서 다시 연결
- 세션이 종료, idle 종료, Pod 비정상 종료로 `READY`가 아니게 됨: 열린 터미널을 이유와 함께 닫음. 공격 대상 요청은 안내 페이지
- 같은 세션에 터미널 4번째 연결: 거절
- 백엔드 재시작: 터미널은 끊기고 다시 연결하면 새 셸. 메모리의 활동 기록 중 DB에 쓰지 않은 것(최대 1분)은 잃음
- 공격 대상 앱이 cookie를 많이 심어 플랫폼 요청 헤더가 너무 커짐: 그 학습자의 플랫폼 요청이 오류. 공격 대상 포트에서 cookie를 지우면 복구

## 작업

- [x] 1. [docs] ADR 022(경로, origin, 연결 방식, 재연결, IDE 연결), 이 작업 목록 (확인: 사람이 정한 결정과 맞음, #70)
- [ ] 2. [infra] 확인 작업: 개발 클러스터의 Sysbox 실습 Pod에서 port-forward로 `127.0.0.1:8080`이 열리는지, exec TTY 셸이 되는지, sqlmap 수준의 요청(동시 10, 1000개)에서 응답 지연과 API server CPU. 결과를 `infra/lab-operations.md`에 기록 (확인: 두 연결이 동작하고 수치가 남음. 안 되면 ADR 022를 다시 봄)
- [ ] 3. [be] `openapi.yaml` 0.5.0: `LabSessionResponse.targetUrl`(`READY`일 때만), 터미널 WebSocket 메시지 형식과 닫는 코드, 공격 대상 포트 동작 설명 (테스트: OpenAPI lint)
- [ ] 4. [infra] `infra/k8s/`: ClusterRole `hackforge-lab-connect`, 백엔드 `bind` 대상 추가, admission policy RoleBinding 규칙 확장, `infra/cluster-setup.md` 8.2, 개발 클러스터 적용 (확인: `lab-connect` RoleBinding이 있는 namespace에서만 백엔드가 port-forward와 exec 가능, 다른 역할·대상·namespace 거절)
- [ ] 5. [be] `LabCluster`: RoleBinding `lab-connect`, 공격 대상 연결(port-forward, 세션별 재사용), 터미널 연결(exec TTY, 크기 변경). `ActivityTracker` (테스트: 가짜 클러스터로 RoleBinding 생성, 활동이 1분에 한 번만 DB에 쓰이고 idle 판단에 메모리 값이 쓰임)
- [ ] 6. [be] 공격 대상 gateway: 공격 대상 포트, 로그인 세션으로 `READY` 세션 찾기, 요청·응답 헤더와 cookie 처리, 이전 실습 cookie 정리, 안내 페이지, 활동 기록 (테스트: 가짜 공격 대상 서버로 경로·폼·cookie 전달, 플랫폼 cookie 제거, 플랫폼 cookie 이름 `Set-Cookie` 제거, `frame-ancestors`, 세션 바뀜 시 cookie 만료, 비로그인·세션 없음·다른 학습자, 플랫폼 API가 공격 대상 포트에서 응답하지 않음, CSRF 검사 없음)
- [ ] 7. [be] 터미널 WebSocket: `Origin` 확인, 세션 확인, 입출력과 크기 변경, 세션당 3개, `READY`가 아니게 되면 닫기, 입력 활동 기록 (테스트: 가짜 exec로 입출력, 잘못된 `Origin`·다른 학습자·`READY` 아님·4번째 연결 거절, 세션 종료 시 닫는 코드)
- [ ] 8. [be] clusterTest: 개발 클러스터의 실제 Pod로 공격 대상 페이지를 gateway로 받고, 터미널에서 명령을 실행하고, 세션을 끝내면 터미널이 닫히는지 확인 (테스트: `./gradlew clusterTest`)
- [ ] 9. [challenge] `hackforge-challenge-template` README 형식 규칙에 "공격 대상 웹은 Pod 안 `127.0.0.1:8080`"을 명시 (확인: 템플릿, sqli-login, 테스트 문제가 이 규칙을 따름)
