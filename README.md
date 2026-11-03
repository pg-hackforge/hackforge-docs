# hackforge-docs

Hackforge의 기획·결정·기능 스펙을 둔다. 코드는 [hackforge-be](../hackforge-be)와 [hackforge-fe](../hackforge-fe)에 있다.

| 파일 | 내용 |
|---|---|
| [product.md](product.md) | 목표, 사용자, 핵심 기능, 안 할 것, 유스케이스, 스택, 데이터 모델 |
| [decisions/](decisions) | 결정 기록(ADR). 결정 하나당 파일 하나, 추가만 함 |
| `specs/<기능>/tasks.md` | 큰 기능의 작업 목록. 기능을 시작할 때 만듦 |
| [infra/](infra) | 클러스터·서버 구성 절차. [cluster-setup.md](infra/cluster-setup.md): 노드 하나에 kubeadm·Calico·Sysbox 설치 |

## 기능 하나를 만드는 순서

1. 이 저장소에 기능 이슈를 연다(feature 템플릿). be·fe에는 하위 이슈를 연다.
2. 큰 기능이면 AI가 `specs/<기능>/tasks.md` 초안을 쓴다.
3. **[검토]** 완료 기준과 예외 상황이 빠지지 않았는지, 작업 하나가 PR 하나 크기인지 사람이 확인하고 머지한다. 큰 결정이 있으면 `decisions/`에 기록한다.
4. API가 바뀌면 `hackforge-be/openapi.yaml`만 먼저 PR로 올려 합의한다.
5. 작업을 하나씩 구현한다. 백엔드를 먼저 하고, 프론트는 생성된 클라이언트로 붙인다. PR 본문에 이슈와 스펙 링크를 건다.
6. 직접 확인한다. 구현 중에 설계가 바뀌었으면 이 저장소를 먼저 고친다.
