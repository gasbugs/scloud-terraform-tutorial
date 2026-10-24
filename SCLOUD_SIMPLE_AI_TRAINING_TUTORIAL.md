# SCP Enterprise 실습: 한국어 분류 모델의 학습 전후 비교


## 시작: 저장소 받기

Docker를 실행할 Linux x86_64 준비 서버의 Bash 터미널에서 시작합니다. 같은 경로에 기존 저장소가 있다면 clone을 반복하지 말고 기존 작업 내용을 확인한 뒤 업데이트하세요.

```bash
git clone https://github.com/gasbugs/scloud-terraform-tutorial.git "$HOME/scloud-terraform-tutorial"
cd "$HOME/scloud-terraform-tutorial/labs/ynat-full-finetune"
```

- [기존 SCP VM 구축 가이드](./README.md): 준비 서버가 필요할 때 참고. 생성 시 비용 발생.
- [Enterprise CLI 설정](./SCLOUD_ENTERPRISE_CLI_GUIDE.md)
- [SCR 생성·업로드 가이드](./SCLOUD_CONTAINER_REGISTRY_TUTORIAL.md)

작성일: 2026-10-23. 대상: Simple AI Training의 **Training Job**.

> 검증 상태: 공식 문서의 콘솔 항목·CLI 명령과 Python 구문/오프라인 평가 로직을 확인했습니다. 교육 계정에서 File Storage `SSD`/`kr-west1-b` 생성과 조회를 확인했습니다. Docker 이미지 빌드, 데이터 다운로드, CUDA 학습과 SAT 연결은 실행하지 않았습니다. 아래 `PASS`는 사용자가 실제 실행 후 확인할 기준이지 이미 얻은 실측 결과가 아닙니다. Enterprise 미제공인 Training Lab은 사용하지 않습니다.

> 실행 이슈: 사용자가 5-1의 File Storage 생성 명령에서 `Bad Request`를 보고했습니다. 오류 코드는 `filestorage.BadRequest.Invalid.zone`이며, 이전 예시의 `kr-west1-a`는 `SSD`로도 거부됐습니다. `SSD`/`kr-west1-b`는 이 교육 계정에서 생성과 조회에 성공했습니다. 다른 계정은 콘솔에서 지원 조합을 확인해야 합니다.

## 1. 무엇을 만드는가

한 Job 안에서 다음을 수행합니다.

```text
한국어 뉴스 제목 700건 평가 → 학습 전 예측 저장
                    ↓
다른 뉴스 제목 1,400건으로 Qwen2.5-0.5B 전체 파라미터 미세조정
                    ↓
동일한 700건 재평가 → 비교표·CSV·모델 파일 저장
```

기존 FM을 새로 사전학습하는 작업이 아닙니다. 약 0.49B인 작은 사전학습 모델의 모든 파라미터를 미세조정합니다. 모델은 뉴스 제목을 읽고 `경제`, `스포츠` 등 7개 주제 중 하나를 생성합니다. LoRA, 양자화, 별도 랜덤 분류 헤드는 사용하지 않습니다.

비교 조건은 고정합니다. 평가 데이터는 학습에 넣지 않으며, 전후 동일한 프롬프트·greedy decoding·출력 상한을 사용합니다. 정답 라벨 이름과 정확히 일치하지 않는 출력은 오답으로 처리합니다. 따라서 점수에는 주제 이해와 출력 형식 준수 능력이 함께 반영됩니다. 성능이 나빠져도 그대로 기록합니다.

## 2. 구축 방식 결정

**이번 규모는 Terraform 없이 `scp-cli` + Docker + 콘솔로 진행합니다.** 기존 개발용 Linux 머신을 재사용하고, 새 VPC·GPU VM·Kubernetes·약정 Workspace를 만들지 않습니다.

| 필요한 것 | 준비 방법 | 확인·대응 |
|---|---|---|
| Linux x86_64 준비 머신 | 기존 PC/개발 서버 사용. GPU 불필요 | Docker를 사용할 수 있는 기존 Linux 환경 확보 |
| SCP 인증키·권한 | 발급받은 교육 계정 사용 | 담당자에게 File Storage/SCR/SAT/ServiceWatch 권한 요청 |
| File Storage | 실습 전용 NFS SSD 볼륨 1개 새로 생성 | SAT 연결 가능한 존·quota 확인 |
| SCR | 기존 레지스트리 우선 사용 | 없으면 콘솔에서 생성 후 접근 대상 설정 |
| SAT Volume 연결 | 콘솔에서 File Storage 연결 | quota 확인 후 1회 연결 |
| Training Job | 콘솔에서 1GPU Job 실행 | smoke 통과 후 full 실행 |

공개 CLI의 AI-ML 목록에는 AI&MLOps Platform과 Cloud ML만 확인됐습니다. `scp-cli sat job create` 같은 미확인 명령을 만들지 않습니다. SAT Volume 연결/Job 생성은 공식 How-to의 콘솔 절차를 사용합니다. 향후 네트워크·개발 서버까지 반복 구축해야 하면 그때 Terraform으로 확장합니다.

### 실행 전 확인하고 진행 중 기록할 값

- Enterprise Account: 발급받은 계정. 이 가이드의 기본 리전은 `kr-west1`, File Storage 존은 이 교육 계정에서 검증한 `kr-west1-b`입니다. 계정에서 SAT에 연결 가능한 존인지 생성 전에 확인합니다.
- 1노드·1GPU 지원 여부, GPU 종류와 VRAM(24GB급 권장), BF16 지원 여부.
- GPU 상품 단가·최소 청구 단위·Job 종료 후 자원 해제 기준.
- 새 File Storage의 존·이름과 SAT 연결 가능 여부. 생성 후 ID와 NFS 마운트 주소를 기록합니다.
- SCR ID, 이미지 push/pull 엔드포인트, 준비 머신과 SAT의 접근 경로.

**실제 상품이 최소 4GPU라면 1GPU 가격으로 계산하지 마세요.** 지원 SKU가 계획과 다르면 자원 생성 전에 예산을 재산정합니다.

## 3. 준비 머신과 파일

**이 문서 전체를 한 번에 복사해 실행하지 마세요.** 실행 위치와 선택 분기는 다음과 같습니다.

| 단계 | 실행 위치 | 실행 규칙 |
|---|---|---|
| 저장소 받기 | Linux 준비 서버의 Bash | 문서 첫 `git clone` 블록 실행 |
| 4~8절 | Linux 준비 서버의 Bash | `~/scloud-terraform-tutorial/labs/ynat-full-finetune`에서 진행 |
| 5절 | 같은 준비 서버 + SCP 콘솔 | 5-1에서 새 File Storage를 생성한 뒤 5-2에서 SAT에 연결 |
| 6절 | 같은 준비 서버 + SCP 콘솔 | 기존 SCR이면 6-1, 없으면 6-2 선택 |
| 9·11절 | SCP 콘솔의 Job Command 입력란 | 서버 터미널에서 실행하는 명령이 아님 |
| 10·12절 | NFS 접근 가능한 내부 Linux 서버 | 준비 서버와 다를 수 있음. 변수·마운트를 별도로 설정 |
| 14절 logout | Linux 준비 서버 | 이미지 push를 수행한 서버로 돌아와 실행 |

복사할 명령 안의 한글 예시 값은 실제 값으로 교체해야 합니다. 각 블록이 실패하면 다음 블록으로 넘어가지 마세요.

이 가이드는 Linux x86_64 + Bash + 동작하는 Docker Engine을 기준으로 합니다. macOS에서는 공식 CLI의 Linux 바이너리를 직접 실행하지 마세요. Apple Silicon에서 아래 x86_64 CUDA 이미지의 에뮬레이션 빌드는 별도 검증 대상입니다. 가장 단순한 경로는 기존 Linux 준비 머신을 사용하는 것입니다.

준비 머신에는 CPU 모델 로딩을 위한 RAM 16GB 이상과 이미지/모델/결과를 위한 여유 디스크 40GB 정도를 권장합니다. 보장 최소 사양은 아닙니다.

준비 서버의 Bash에서 이 문서 맨 위의 `git clone` 명령으로 저장소를 받습니다. 이미 받았다면 아래 작업 디렉터리로 이동하면 됩니다. 개인 컴퓨터의 절대 경로나 SSH 파일 복사 명령은 필요하지 않습니다.

이후 4~8절은 준비 서버의 같은 Bash 세션에서 실행합니다. 6절의 SCR 재사용/생성 경로 중 하나만 선택합니다. 새로 접속했다면 아래 작업 디렉터리와 4절의 PATH를 다시 설정하세요.

```bash
cd ~/scloud-terraform-tutorial/labs/ynat-full-finetune
uname -m
python3 --version
docker version
docker info
PYTHONDONTWRITEBYTECODE=1 python3 check_offline.py
```

기대: `x86_64`, Docker Client/Server 모두 표시, 마지막 명령의 `PASS`. Docker가 없으면 [공식 Linux 설치 문서](https://docs.docker.com/engine/install/)에서 OS에 맞게 설치한 후 돌아옵니다. Docker daemon 권한을 확보하고 진행합니다. `docker info` 실패 상태로 다음 단계에 넘어가지 않습니다.

동봉 파일:

| 파일 | 역할 |
|---|---|
| `configure_cli.py` | 인증키를 숨겨 입력하고 CLI 설정을 안전하게 생성 |
| `prepare.py` | CPU에서 데이터·모델 준비, revision/hash 기록 |
| `train.py` | 평가 → 전체 파라미터 학습 → 재평가 → 저장 |
| `run.py` | 실행 시간 제한, 중복 실행 디렉터리 방지 |
| `common.py` | 프롬프트·평가 계산 |
| `check_offline.py` | 네트워크 없이 가능한 구문·평가 로직 점검 |
| `Dockerfile.runtime` | CPU 준비와 GPU 실행에 공통으로 사용할 환경 |
| `Dockerfile` | 로컬 runtime 이미지를 기반으로 하는 실행 환경 이미지. 모델·데이터 미포함 |

## 4. SCP CLI 설치·인증

공식 Linux 다운로드 링크를 사용합니다. CLI를 기존 설치에 덮어쓰지 않고 실습 폴더에 둡니다.

```bash
mkdir -p tools evidence
curl --fail --location --output tools/scp-cli \
  https://docs.e.samsungsdscloud.com/tools/cli/linux/scp-cli
chmod 700 tools/scp-cli
export PATH="$HOME/scloud-terraform-tutorial/labs/ynat-full-finetune/tools:$PATH"
scp-cli --help > evidence/scp-cli-help.txt
sha256sum tools/scp-cli > evidence/scp-cli-sha256.txt
```

`Exec format error`면 OS/CPU 아키텍처가 맞지 않는 것입니다. 인증키를 다시 만들 문제가 아닙니다.

콘솔에서 발급한 인증키를 사용합니다. 기존 설정이 있으면 다음 Python 블록은 **덮어쓰지 않고 중단**합니다. 기존 설정이 Enterprise 계정과 대상 리전인지 개인 화면에서 확인하고 재사용하세요. 키 값을 교안·화면 녹화·이미지에 넣지 않습니다.

```bash
python3 - <<'PYCONFIG'
"""Interactive CLI credentials setup. Never prints key values or overwrites existing config."""
import getpass
import json
import os
from pathlib import Path

path = Path.home()/'.scp'/'cli-config.json'
if path.exists():
    raise SystemExit('Existing ~/.scp/cli-config.json found: inspect privately and reuse it; not overwritten.')
region = 'kr-west1'
assert region, 'Region is required'
access = getpass.getpass('Access Key (hidden): ')
secret = getpass.getpass('Access Secret Key (hidden): ')
assert access and secret
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(dict(auth_url='https://iam.e.samsungsdscloud.com/v1/endpoints',
                   access_key=access, access_secret_key=secret, default_scp_region=region), f)
print('PASS: created private CLI configuration; key values not displayed')

PYCONFIG
```

기존 설정 파일이 있다면 내용을 개인 화면에서 확인하고 아래 조회 블록만 실행합니다. 조회 중 하나라도 실패하면 5절로 넘어가지 않습니다.

```bash
(
  set -euo pipefail
  scp-cli --version > evidence/scp-cli-version.txt
  scp-cli filestorage volume list > evidence/volumes-before.txt
  scp-cli scr registry list > evidence/registries-before.txt
)
```

설정 파일은 `~/.scp/cli-config.json`이며 Enterprise 인증 주소는 `https://iam.e.samsungsdscloud.com/v1/endpoints`입니다. 출력 파일에 키 값은 쓰지 않지만 내부 자원 정보가 포함될 수 있으므로 외부 배포본에는 포함하지 않습니다.

`evidence/scp-cli-version.txt`에는 CLI 버전이 기록됩니다. 두 목록 파일은 조회 출력을 저장하며 자원이 없으면 비어 있을 수 있습니다. 목록 조회가 `401/403`으로 실패하면 키 상태·대상 계정·권한·인증키 보안 설정을 먼저 확인하세요. 재발급만 반복하지 않습니다.

## 5. 새 File Storage 생성 및 SAT 연결

### 5-1. 새 File Storage 생성 — CLI

4절의 CLI 설치·인증을 완료한 Linux 준비 서버의 Bash에서 실행합니다. 실습 전용 File Storage를 새로 1개 생성하며, 저장 데이터 사용량에 따라 비용이 발생합니다. 본 예제는 실행 1회당 모델 가중치 약 2GB(FP32)와 소량의 로그를 저장하므로 결과용 여유 공간 10GB 이상을 권장합니다. File Storage의 최소 청구 용량은 별도입니다.

`kr-west1`은 CLI 설정의 **리전**, `kr-west1-b`는 생성 명령의 **존**입니다. `SSD`/`kr-west1-b`는 이 교육 계정에서 검증한 조합입니다. [CLI Common](https://docs.e.samsungsdscloud.com/clireference/cli-common/)과 [CreateVolume 1.2](https://docs.e.samsungsdscloud.com/clireference/storage/filestorage/clis/createvolume/1.2/)에서 옵션 형식을 확인하고, 다른 계정은 콘솔의 File Storage 생성 화면에서 볼륨 유형별 지원 존과 SAT 연결 가능 여부를 확인합니다. 삼성SDS는 [고성능 SSD를 Multi-node GPU Cluster 전용](https://www.samsungsds.com/kr/techreport/what-is-cloud-storage.html)으로 설명합니다.

설치된 CLI의 생성 옵션과 현재 볼륨 목록을 확인합니다. 목록은 생성 전 상태와 타임아웃 후 중복 여부를 확인하는 데 사용합니다.

```bash
cd ~/scloud-terraform-tutorial/labs/ynat-full-finetune
export PATH="$HOME/scloud-terraform-tutorial/labs/ynat-full-finetune/tools:$PATH"
(
  set -euo pipefail
  scp-cli filestorage volume create --help
  scp-cli filestorage volume list
)
```

새 이름을 생성해 기록한 뒤 생성 요청을 **한 번만** 보냅니다. 출력된 이름은 응답이 지연되거나 타임아웃될 때 조회에 사용합니다.

```bash
(
  set -euo pipefail
  SAT_VOLUME_NAME="satynat$(date -u +%y%m%d%H%M%S)"
  printf '새 File Storage 이름: %s\n' "$SAT_VOLUME_NAME"
  printf '%s\n' "$SAT_VOLUME_NAME" > evidence/file-volume-name.txt
  scp-cli filestorage volume create \
    --zone kr-west1-b \
    --type_name SSD \
    --protocol NFS \
    --name "$SAT_VOLUME_NAME"
)
```

생성 응답의 `volume_id`를 입력해 조회합니다. SAT Volume ID가 아니라 File Storage ID입니다. 조회 결과의 실제 이름과 `available` 상태를 확인하세요. 서비스가 요청 이름에 접미사를 붙일 수 있습니다.

```bash
(
  set -euo pipefail
  read -r -p '생성 응답의 volume_id: ' SAT_FILE_VOLUME_ID
  [[ -n "$SAT_FILE_VOLUME_ID" ]] || { echo 'volume_id가 필요합니다.' >&2; exit 1; }
  scp-cli filestorage volume show --volume_id "$SAT_FILE_VOLUME_ID"
)
```

생성 요청이 타임아웃되면 `scp-cli filestorage volume list --name "$(cat evidence/file-volume-name.txt)"`로 먼저 확인하고, 생성 명령을 무조건 재실행하지 않습니다. `filestorage.BadRequest.Invalid.zone`은 지정한 볼륨 유형에 사용할 수 없는 존이라는 뜻입니다. 이 계정에서 `kr-west1-a`는 `SSD`로도 거부됐습니다. 다른 존을 추측해 생성 요청을 반복하지 말고 콘솔의 File Storage 생성 화면에서 지원 조합을 확인하세요. `--debug true` 출력에는 인증 헤더·토큰이 포함될 수 있으므로 공유하거나 공개 저장소에 남기지 않습니다. 성공 전에는 5-2로 진행하지 않습니다. 최종 준비 완료 상태를 콘솔에서 확인합니다.

### 5-2. SAT에 연결 — 콘솔 1회

1. **Simple AI Training → Volume → Volume 연결**로 이동합니다.
2. Volume명 `ynat-results`, 위에서 새로 만든 File Storage를 선택합니다.
3. 생성된 SAT Volume 이름/ID를 기록합니다. File Storage ID와 SAT Volume ID는 구분합니다.
4. quota `SAT.FILE_STORAGE.MOUNT.MAX.COUNT`가 1 이상이어야 합니다. 부족하면 Quota Service에서 변경 요청합니다.

Training Job에서 이 Volume을 `/results`에 마운트합니다. 컨테이너 사용자가 해당 경로에 쓸 수 있어야 합니다. NFS root squash/소유권 문제는 실습 전용 디렉터리의 UID/GID와 접근 규칙으로 해결하고 공유 볼륨 전체를 `chmod 777`로 바꾸지 않습니다.

## 6. SCR 준비

### 6-1. 경로 A — 기존 SCR 사용 (6-2 생성 생략)

```bash
scp-cli scr registry list
export SAT_REGISTRY_ID='실제-레지스트리-ID'
scp-cli scr registry show --registry_id "$SAT_REGISTRY_ID"
```

콘솔의 **Container Registry 상세 → 이미지 사용 명령**에서 실제 호스트와 인증 방식을 확인합니다. DNS 이름은 만들어 추측하지 마세요. push용 Public endpoint와 SAT pull용 Private endpoint가 다를 수 있습니다.

### 6-2. 경로 B — 새 SCR이 필요할 때만 콘솔에서 생성

SCR 생성은 콘솔에서 진행합니다. 이전 문서의 `--public_acl_resources '[]'` 등 빈 배열 옵션은 실제 CLI 파싱을 확인하지 못했으므로 실행 명령에서 제거했습니다.

1. Container Registry 생성 화면에서 이름 `sat-ynat-demo`를 입력합니다.
2. 공개 가시성은 끄고, 준비 서버와 SAT가 사용할 접근 경로에 맞게 endpoint 및 접근 대상을 설정합니다.
3. 생성한 레지스트리의 실제 push/pull 주소를 기록합니다.

### 6-3. 두 경로 공통 — 접근 및 인증 설정

기존 레지스트리도 다음 항목을 확인합니다. 콘솔에서:

- 준비 머신이 내부망이면 Private 접근 허용 대상으로 추가합니다.
- 외부 준비 머신이면 필요한 경우 Public endpoint를 켜되 실제 출발지 IP만 허용하고, 공개 가시성은 끈 상태로 유지합니다.
- SAT 학습 자원이 이미지를 가져올 경로도 SDS 권장 방식으로 허용합니다. SAT가 SCR 접근 대상 목록에 직접 나오지 않으면 담당자에게 서비스 연계 방식을 확인합니다.
- 본인 계정의 이미지 push 권한 및 Job의 pull 인증을 설정합니다.
- Repository `ynat-full-ft`를 생성합니다. 접근 정책을 이유 없이 전면 허용하지 않습니다.

인증키의 SCR 사용 보안 설정은 계정의 콘솔 안내에 따라 완료해야 합니다. 현재 문서만으로 특정 보안 스위치 이름을 단정하지 않습니다.

## 7. GPU 없이 이미지와 데이터 준비

이 단계는 네트워크 다운로드와 CPU·디스크를 사용하지만 클라우드 GPU를 생성하지 않습니다. 코드의 기본 모델/데이터는 공개 저장소이며 HF 인증키가 필요 없는 구성을 목표로 합니다.

```bash
docker build --platform linux/amd64 \
  -f Dockerfile.runtime -t sat-ynat-runtime:v1 .
docker run --rm sat-ynat-runtime:v1 \
  python -c 'import torch, transformers, datasets; print(torch.__version__, transformers.__version__, datasets.__version__)'
mkdir -p bundle
docker run --rm --user "$(id -u):$(id -g)" \
  --env HOME=/tmp --env HF_HOME=/tmp/huggingface \
  --env HF_HUB_CACHE=/tmp/huggingface/hub \
  --env HF_DATASETS_CACHE=/tmp/huggingface/datasets \
  --mount type=bind,src="$PWD/bundle",dst=/bundle \
  sat-ynat-runtime:v1 python /opt/lab/prepare.py --out /bundle
```

기대: 마지막에 `PASS: prepared offline bundle; no GPU used`. `bundle/manifest.json`을 확인합니다.

```bash
python3 -m json.tool bundle/manifest.json
```

확인할 값:

- train=1,400 / dev=350 / test=700.
- 각 표본의 길이 최대 128 이하.
- 모델·데이터 revision과 JSONL SHA-256이 기록됨.
- 데이터 중복 제거, 원본 train과 validation의 중복 제외가 적용됨.

뉴스 제목의 길이가 초과하면 자르지 않고 제외합니다. 전체 원본 데이터를 모두 학습하지 않습니다. 개발 세트 350건은 다음 실험용으로 보관하며 이번 고정 1회 실행에서는 사용하지 않습니다.

실패하면 GPU를 생성하지 않은 상태에서 수정합니다. `manifest.json`이 이미 있으면 재준비를 거부합니다. 다른 버전을 준비할 때는 기존 bundle을 날짜별 디렉터리로 보관한 뒤 새 디렉터리에서 수행합니다.

## 8. File Storage에 코드·데이터 업로드

사용자가 요청한 업로드 대상은 **File Storage**입니다. 학습 코드와 모델·데이터는 NFS에 올리고, SCR에는 의존성과 학습 코드가 포함된 실행 이미지를 올립니다. Job은 NFS에 업로드한 릴리스 코드를 실행합니다. Docker 빌드 컨텍스트에서 bundle을 제외하므로 `Dockerfile.runtime`과 `push-training-image.sh`가 만드는 이미지에는 모델·데이터가 없습니다. 아래 본문 명령은 보조 스크립트 없이 직접 실행할 수 있습니다.

### 8-1. 준비 서버에 File Storage 마운트

준비 서버는 File Storage NFS에 접근 가능한 내부 Linux 서버여야 합니다. File Storage 콘솔의 접근 제어에 해당 서버가 허용되어 있어야 합니다. 다음은 Ubuntu/Debian 예시입니다. NFS 주소는 생성된 자원에만 존재하는 값이므로 콘솔의 마운트 명령에서 복사합니다.

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
sudo mkdir -p /mnt/sat-results
read -r -p 'File Storage 콘솔의 NFS 서버:/export 주소: ' SAT_NFS_SOURCE
sudo mount -t nfs "$SAT_NFS_SOURCE" /mnt/sat-results
findmnt /mnt/sat-results
```

콘솔이 지정한 버전·옵션이 있으면 그 마운트 명령을 사용합니다. 이미 마운트돼 있다면 중복 mount하지 않습니다. 현재 사용자에게 업로드 디렉터리의 쓰기 권한이 필요합니다.

### 8-2. 업로드 및 무결성 검사

다음 블록 전체를 준비 서버의 Bash에 붙여 넣습니다. 괄호는 오류 시 이 작업만 중단하기 위한 서브셸이며 별도 스크립트 파일을 호출하지 않습니다.

```bash
(
  set -euo pipefail
  cd ~/scloud-terraform-tutorial/labs/ynat-full-finetune

  SAT_MOUNT=/mnt/sat-results
  SAT_RELEASE=ynat-v1
  SAT_DEST="$SAT_MOUNT/releases/$SAT_RELEASE"

  # 로컬 디스크에 잘못 복사하지 않도록 실제 NFS 마운트를 확인합니다.
  mountpoint -q "$SAT_MOUNT"
  SAT_FS_TYPE="$(findmnt -n -o FSTYPE --target "$SAT_MOUNT")"
  [[ "$SAT_FS_TYPE" == nfs || "$SAT_FS_TYPE" == nfs4 ]]
  test -s bundle/manifest.json

  # 기존 릴리스가 있으면 mkdir가 실패하며 덮어쓰지 않습니다.
  mkdir -p "$SAT_MOUNT/releases"
  mkdir "$SAT_DEST"
  mkdir "$SAT_DEST/code"

  # 학습 코드와 모델·데이터를 File Storage에 복사합니다.
  cp common.py train.py run.py "$SAT_DEST/code/"
  cp -R bundle "$SAT_DEST/bundle"

  # 로컬 원본의 해시 목록을 만들고 업로드한 파일과 비교합니다.
  (
    sha256sum common.py train.py run.py | sed 's|  |  code/|'
    find bundle -type f -exec sha256sum {} +
  ) > "$SAT_DEST/SHA256SUMS"

  (
    cd "$SAT_DEST"
    sha256sum --check SHA256SUMS
  )

  # 모든 파일이 일치했을 때만 업로드 완료 표시를 기록합니다.
  printf 'SHA256 verification passed\n' > "$SAT_DEST/READY"
  cat "$SAT_DEST/READY"
  ls -lh "$SAT_DEST/code" "$SAT_DEST/bundle"
)
```

파일별 `OK`와 마지막 `SHA256 verification passed`가 나오는지 확인합니다. 코드는 `releases/ynat-v1/code/`, 모델과 JSONL은 `releases/ynat-v1/bundle/`에 있습니다. 실패하면 다음 학습 단계로 넘어가지 않습니다. 수정 후 다시 업로드할 때는 `SAT_RELEASE=ynat-v2`처럼 새 이름을 사용하고, 9·11절 Job Command의 릴리스 이름도 동일하게 바꿉니다.

### 8-3. 실행 환경 이미지 업로드

Training Job은 File Storage의 코드만으로 실행되지 않으므로 7절에서 빌드한 runtime 이미지도 필요합니다. 아래는 준비 서버 Bash에서 실행합니다.

```bash
(
  set -euo pipefail
  read -r -p 'SCR push 호스트(https:// 제외): ' SAT_PUSH_HOST
  read -r -s -p 'SCR 사용자명: ' SAT_SCR_USER
  printf '\n'
  read -r -s -p 'SCR 비밀번호: ' SAT_SCR_PASSWORD
  printf '\n'
  printf '%s' "$SAT_SCR_PASSWORD" | docker login "$SAT_PUSH_HOST" --username "$SAT_SCR_USER" --password-stdin
  unset SAT_SCR_PASSWORD SAT_SCR_USER
  trap 'docker logout "$SAT_PUSH_HOST" >/dev/null 2>&1 || true' EXIT
  docker tag sat-ynat-runtime:v1 "$SAT_PUSH_HOST/ynat-full-ft:runtime-v1"
  docker push "$SAT_PUSH_HOST/ynat-full-ft:runtime-v1"
)
```

Job 이미지에는 SAT에서 접근 가능한 pull 호스트와 위 runtime 이미지의 digest를 사용합니다. 자격증명은 콘솔 이미지 인증 필드에 입력합니다. File Storage는 Job에서 `/results`에 마운트합니다.

## 9. 먼저 smoke Job 실행

실제 GPU 과금은 이 단계에서 시작할 수 있습니다. 첫 실행은 전체 학습이 아니라 **70건(클래스당 10건), 평가 14건, 약 5회 업데이트**입니다. 기존 계획의 64건 대신 7개 클래스 균형을 맞추고 5 updates를 만들기 위해 70건으로 조정했습니다.

콘솔 **Simple AI Training → Training Job 생성**에서 다음을 입력합니다.

| 항목 | 입력 |
|---|---|
| Job명 | 예: `ynat-smoke-01` |
| 학습 형태 | On-Demand Training |
| 분산 Framework | 이미지의 PyTorch 2.5.1/CUDA 12.4와 호환되는 PyTorch 옵션. 제공 버전과 launcher 요구는 SDS 확인 |
| 노드/GPU | 노드 1, GPU 1, BF16 지원 GPU. 가용 SKU 중 예산에 맞는 최소 사양 |
| 메모리 | CPU RAM 16GB 이상 우선 검토, VRAM 24GB급 권장 |
| Shared Memory | 콘솔 허용 단위/최소값 확인. DataLoader worker=0으로 구성되어 큰 공유 메모리를 전제하지 않음 |
| Job Failover | 사용 안 함. 첫 검증에서 자동 재시작 방지 |
| 이미지 URL | 위에서 업로드한 pull 주소와 고정 digest/태그 |
| 이미지 인증 | 해당 SCR pull 자격증명 |
| Volume | 앞에서 연결한 `ynat-results`, Mount Path `/results` |
| Command | 아래 명령 |

```text
python /results/releases/ynat-v1/code/run.py --bundle /results/releases/ynat-v1/bundle --mode smoke --output /results/ynat-smoke-01
```

`run.py`는 단일 프로세스만 허용합니다. 코드와 bundle이 같은 File Storage 릴리스에 있고 업로드 검증 완료 표시인 `READY`가 있는지 확인한 후 시작합니다. 다운로드를 막는 오프라인 모드를 실행 시 설정합니다. 서비스가 강제로 다중 프로세스 launcher를 주입하면 중단하고 단일 GPU 실행 규칙을 확인하세요. 추측으로 `torchrun`을 중복 실행하지 않습니다.

**동일 출력 디렉터리는 재사용하지 않습니다.** 재시도 시 Job명과 output을 `ynat-smoke-02`처럼 바꿉니다. 자동 재시작이 같은 output을 쓰면 시작을 거부하므로 이전 결과를 덮어쓰거나 무제한 학습하지 않습니다.

기대: Job `Completed`, 출력 `status.json`의 `COMPLETED`, 마지막 `PASS`. stdout과 File Storage의 `run.log`에 실행 로그를 함께 기록하며 `training.jsonl`에는 update별 수치를 기록합니다. 이미지 로딩 중에는 로그가 잠시 조용할 수 있습니다. `/results`가 실제 마운트되지 않았으면 실행을 거부합니다.

smoke는 10분 프로세스 시간 제한이 있습니다. 제한 도달 시 `TIMEOUT`, exit 124로 종료합니다. 프로비저닝·이미지 pull·플랫폼 과금 시간을 포함한 제한이 아니므로 콘솔도 직접 확인해야 합니다.

## 10. 결과 경로 접근 및 smoke 판정

8절에서 준비 서버에 마운트했다면 아래 설치·mount 블록은 생략하고 같은 서버에서 결과 조회 블록만 실행합니다.

이미 File Storage를 마운트한 개발 서버가 있으면 해당 경로를 사용합니다. 없다면 해당 NFS에 접근하도록 허용된 **기존 내부 Linux 서버**에서 콘솔의 마운트 안내를 따릅니다. 외부 인터넷에서 NFS가 직접 접근된다고 가정하지 않습니다.

**여기부터는 NFS 접근 가능한 내부 Linux 서버의 Bash에서 실행합니다.** 준비 서버와 다른 서버라면 해당 서버에 SSH로 접속하세요. 4~8절의 환경변수가 전달된다고 가정하지 않습니다.

아래는 Ubuntu/Debian 계열 서버 예시입니다. 콘솔이 별도 NFS 버전/옵션을 안내하면 그 옵션을 사용하세요.

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
sudo mkdir -p /mnt/sat-results
export SAT_NFS_SOURCE='콘솔의-실제-NFS주소:/export경로'
sudo mount -t nfs "$SAT_NFS_SOURCE" /mnt/sat-results
findmnt /mnt/sat-results
ls /mnt/sat-results
```

이 마운트 경로의 루트가 Job의 `/results`에 대응해야 합니다. File Storage 접근 규칙에는 이 결과 확인 서버만 추가하고 기존 규칙은 보존합니다. 다른 결과 경로를 지운 뒤 맞추지 마세요.

```bash
export SAT_RUN_DIR='/mnt/sat-results/ynat-smoke-01'
cat "$SAT_RUN_DIR/status.json"
tail -n 30 "$SAT_RUN_DIR/run.log"
cat "$SAT_RUN_DIR/comparison.md"
```

다음 모두 통과해야 본 실행으로 진행합니다.

- 학습 전/후 각각 14건, training updates 5회.
- `backbone_weight_changed: true`.
- `checkpoint_reload_verified: true`.
- 유한한 loss, 허용 가능한 최대 GPU 메모리.
- `status.json`이 `COMPLETED`이며 Job의 GPU 자원이 회수됨.

실행시간은 `comparison.json`과 `training.jsonl`에서 확인합니다. 작은 smoke의 평가는 14건이고 본 평가는 700건이므로 전체 시간을 단순히 학습 steps 비율로만 계산하지 않습니다. 본 실행은 전후 총 1,400건의 생성 평가도 포함합니다.

## 11. 본 학습 전후 비교 실행

smoke가 통과하고 예상 GPU 비용이 예산 안이면 같은 이미지로 새 Job을 만듭니다. 본 실행은 기존 사전학습 모델에서 **다시 시작**하며 smoke 모델을 이어 학습하지 않습니다.

```text
python /results/releases/ynat-v1/code/run.py --bundle /results/releases/ynat-v1/bundle --mode full --output /results/ynat-full-01
```

다른 설정은 동일합니다. 1 epoch, micro batch 2, accumulation 8로 약 88 updates를 수행하며 최대 100 updates를 넘지 않습니다. 학습률 시작 기준 2e-5, BF16 autocast와 FP32 가중치, AdamW를 사용합니다. 본 실행에는 gradient checkpointing을 적용해 활성값 메모리를 절감하며 속도와의 교환이 있습니다.

프로세스 제한은 **평가·학습·저장·재로딩을 모두 포함해 30분**입니다. 시간이 모자라면 실패로 기록하고 무조건 연장하지 않습니다. smoke 결과로 규모를 줄일 필요가 있으면 학습·평가 표본을 다시 고정하고 새로운 File Storage 릴리스로 업로드하여 실험해야 합니다. 전후 평가 건수는 반드시 같아야 합니다.

## 12. 결과 읽기

```bash
export SAT_RUN_DIR='/mnt/sat-results/ynat-full-01'
cat "$SAT_RUN_DIR/status.json"
cat "$SAT_RUN_DIR/comparison.md"
python3 -m json.tool "$SAT_RUN_DIR/comparison.json"
head -n 6 "$SAT_RUN_DIR/predictions.csv"
ls -lh "$SAT_RUN_DIR/model"
```

| 결과 파일 | 의미 |
|---|---|
| `before.json` / `after.json` | 같은 평가 데이터의 전후 원문 예측과 점수 |
| `comparison.md` | 사람이 읽을 수 있는 비교표 |
| `comparison.json` | 정확도, macro-F1, 잘못된 출력률, 시간, 메모리, 원본 revision |
| `predictions.csv` | 제목·정답·학습 전 예측·학습 후 예측·정오 여부 |
| `training.jsonl` | update별 loss, 누적 학습 시간, peak GPU 메모리 |
| `model/` | 전체 모델과 토크나이저. CPU에서 저장 결과 재로딩까지 확인 |
| `status.json` | 실제 worker 종료 상태·코드·제한시간 |

`accuracy_delta_pp`는 퍼센트포인트 차이입니다. 예를 들어 가상의 40%→60%는 +20%p이며, 이 수치는 본 실습의 예상/실측 결과가 아닙니다. 700건의 균형 표본은 공식 전체 KLUE 벤치마크와 다릅니다.

점수가 낮아도 형식 오류인지 의미 분류 오류인지 `invalid_rate`와 CSV를 함께 보세요. 추가 튜닝은 준비된 dev 세트로 결정하고, 최종 test를 반복해서 보고 고르는 방식은 피합니다. 현 스크립트는 1회 고정 실험용이며 자동 탐색을 하지 않습니다.

## 13. 실패했을 때 먼저 확인할 것

| 증상 | 먼저 확인 | 다음 행동 |
|---|---|---|
| CLI 실행 불가 | Linux/x86_64 여부, 실행권한 | 올바른 준비 머신 사용 |
| 401/403 | 키·보안 설정·IAM·계정 | 필요한 권한만 수정 |
| ImagePull 오류 | 호스트·digest·자격증명·SCR ACL | 이미지 접근부터 해결, GPU 증설 금지 |
| Volume 생성/연결 불가 | File Storage 종류·존·SAT quota | 지원 조합과 quota 확인 |
| Permission denied | `/results` 소유권·NFS ACL/root squash | 실습 경로 UID/GID 조정 |
| BF16/CUDA 검사 실패 | 실제 GPU·드라이버·CUDA 호환 | 이미지/GPU 조합 재확인 |
| CUDA out of memory | 배치·최대 토큰·실제 VRAM | micro batch 1로 수정한 코드를 새 File Storage 릴리스에 업로드하고 Job Command 경로 변경; GPU 수 자동 증가 금지 |
| TIMEOUT | 초기화/평가/학습/저장 어느 구간인지 | CPU 준비와 표본·평가량 조정 |
| output already exists | 같은 output을 재사용했는지 | 기존 기록 보존하고 새 실행 ID 사용 |
| 학습 후 성능 하락 | 라벨 매핑·출력 형식·loss·과적합 | dev 기준으로 조정, 결과를 숨기지 않음 |

## 14. 종료와 비용 확인

1. Job `Completed/Failed`만 보고 끝내지 말고 GPU 할당이 해제됐는지 확인합니다.
2. `TIMEOUT` 또는 로그가 멈춘 상태면 콘솔의 Job 삭제/해지 절차로 남은 작업을 정리하고 실제 해제까지 확인합니다.
3. 출력은 삭제 전에 별도 보관합니다. 학습 스크립트 timeout은 클라우드 과금 차단을 보장하지 않습니다.
4. 이번에 새로 만든 File Storage와 SAT Volume은 필요한 결과를 보관하고 사용 주체를 확인한 뒤 정리합니다. 기존 SCR은 삭제하지 않습니다.
5. 학습 과정에서 만들지 않은 약정 Workspace·공유 볼륨은 건드리지 않습니다.
6. **이미지를 push했던 준비 서버로 돌아와** 아래를 수행합니다. 새 세션에서도 실행할 수 있도록 호스트를 다시 입력합니다.

```bash
read -r -p '로그아웃할 SCR push 호스트: ' SAT_PUSH_HOST
docker logout "$SAT_PUSH_HOST"
```

전체 실행 할당 누적 90분을 잠정 예산으로 잡되, SKU 단가·이미지 pull·초기화·최소 청구 단위·스토리지 및 로그 비용을 합산합니다. 여기서는 원화 비용을 추측해 기입하지 않았습니다.

## 15. 출처 및 배포 주의

- [Training Job/Volume 공식 How-to](https://docs.e.samsungsdscloud.com/userguide/ai_ml/simple_ai_training/how_to_guides/)
- [SCP CLI 설치·인증](https://docs.e.samsungsdscloud.com/clireference/cli-common/)
- [File Storage CLI 1.2 생성](https://docs.e.samsungsdscloud.com/clireference/storage/filestorage/clis/createvolume/1.2/)
- [SCR CLI 1.1 생성](https://docs.e.samsungsdscloud.com/clireference/container/scr/clis/createregistry/1.1/)
- [AI-ML 공개 CLI 목록](https://docs.e.samsungsdscloud.com/clireference/ai-ml/)
- [KLUE 데이터 카드](https://huggingface.co/datasets/klue/klue)
- [Qwen2.5-0.5B 모델 카드](https://huggingface.co/Qwen/Qwen2.5-0.5B)

KLUE YNAT은 CC BY-SA 4.0으로 상업적 교육·학습 이용이 가능합니다. Qwen 모델 카드는 Apache 2.0입니다. 가공 데이터 출처·변경 내역을 manifest에 기록하지만, 이것만으로 배포 고지가 완성되지는 않습니다. 외부 전달 전 데이터 출처·라이선스 링크·변경 내역과 원본 고지 및 라이선스 사본을 동봉하고, 가공 데이터는 CC BY-SA 4.0으로 제공합니다. 사설 SCR에 보관해도 SDS에 이미지를 전달할 때의 라이선스 검토는 필요합니다. SDS 귀속 교안과 제3자 데이터/모델의 권리를 구분하세요. 구체적인 납품 조건과 고지 예시는 [데이터셋 라이선스 검토](./labs/ynat-full-finetune/DATASET_LICENSE.md)를 참고하세요.
