# hackforge-docs

Hackforge의 기획, 결정, 기능 spec을 두는 저장소다. 코드는 [hackforge-be](../hackforge-be)와 [hackforge-fe](../hackforge-fe)에 있다.

| 파일 | 내용 |
|---|---|
| [product.md](product.md) | 목표, 사용자, 핵심 기능, 안 할 것, 유스케이스, 스택, 데이터 모델 |
| [decisions/](decisions) | ADR. 결정 하나당 파일 하나, 추가만 함 |
| `specs/<기능>/tasks.md` | 큰 기능의 작업 목록. 기능 시작할 때 생성 |
| [infra/](infra) | 클러스터·서버 구성 runbook. [cluster-setup.md](infra/cluster-setup.md): single node에 kubeadm, Calico, Sysbox 설치 |

## 기능 하나를 만드는 순서

1. 이 저장소에 feature 이슈를 만들고, be·fe에는 하위 이슈를 만든다.
2. 큰 기능이면 AI가 `specs/<기능>/tasks.md` 초안을 쓴다.
3. **[검토]** 사람이 완료 기준과 예외 상황이 빠지지 않았는지, 작업 하나가 PR 하나 크기인지 보고 머지한다. 큰 결정이 있으면 `decisions/`에 남긴다.
4. API가 바뀌면 `hackforge-be/openapi.yaml`만 먼저 PR로 올려 합의한다.
5. 작업을 하나씩 구현한다. 백엔드를 먼저 하고, 프론트는 생성된 API client로 붙인다. PR 본문은 템플릿대로 쓰고, 근거 섹션에 이슈와 작업 번호를 적는다.
6. 직접 확인한다. 구현하다가 설계가 바뀌면 이 저장소부터 고친다.
