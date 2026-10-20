# Samsung Cloud Platform Enterprise CLI 설정 가이드

이 문서는 Samsung Cloud Platform(SCP) Enterprise 환경에서 공식 CLI를 설치하고 인증한 뒤 Container Registry를 생성하는 방법을 설명합니다. Docker Hub 이미지 업로드, 검증, Repository와 Registry 정리는 [SCP Container Registry 생성·업로드·정리 튜토리얼](./SCLOUD_CONTAINER_REGISTRY_TUTORIAL.md)에서 이어집니다.

`PLATFORM-GW-00002: Access key not found`가 발생하더라도 Terraform이 같은 Access Key로 정상 동작한다면 키보다 CLI 종류와 endpoint 조합을 먼저 확인합니다.

## 문제 원인

인터넷에서 찾을 수 있는 일부 가이드는 Java 기반 `scp-tool-cli-2.0.0`을 설치한 뒤 실행 파일 이름을 `scloud`로 연결합니다.

```text
실행 파일  scp-tool-cli
설정 경로  ~/.cmp
API 주소   https://openapi.samsungsdscloud.com
```

이 구성은 Enterprise IAM을 사용하는 환경과 맞지 않을 수 있습니다. 정상적인 Enterprise Access Key를 공용 CMP Gateway로 보내면 다음 오류가 발생할 수 있습니다.

```text
PLATFORM-GW-00002: Access key not found
```

이 오류는 키 자체가 잘못됐다는 뜻으로 단정할 수 없습니다. 같은 키를 사용하는 Terraform이 `iam.e.samsungsdscloud.com`에서 정상 인증된다면 서로 다른 환경의 endpoint를 혼용했을 가능성이 큽니다.

다음 GitHub 저장소는 Samsung SDS 공식 저장소가 아닌 개인 계정의 비공식 가이드입니다. 이 저장소가 안내하는 `~/.cmp`와 공용 `openapi` 설정을 Enterprise 환경에 그대로 적용하지 않습니다.

- 비공식 가이드: <https://github.com/t2yijaeho/SCP-CLI>
- Enterprise 공식 CLI 문서: <https://docs.e.samsungsdscloud.com/en/clireference/cli-common/>

### 공식 GitHub 저장소 여부

현재 공개된 Samsung SDS 공식 GitHub 조직 `SamsungSDSCloud`에는 Terraform Provider 저장소만 있으며 SCP CLI 소스 저장소는 확인되지 않습니다.

- Samsung SDS 공식 GitHub 조직: <https://github.com/SamsungSDSCloud>
- 공식 Terraform Provider v2: <https://github.com/SamsungSDSCloud/terraform-provider-samsungcloudplatformv2>

공식 CLI는 GitHub Release가 아니라 Samsung SDS Enterprise 문서 서버에서 컴파일된 실행 파일 형태로 배포됩니다.

```text
https://docs.e.samsungsdscloud.com/tools/cli/linux/scp-cli
```

GitHub 저장소 이름이나 설명에 `Samsung Cloud Platform CLI`가 적혀 있다는 이유만으로 공식 배포처라고 판단하지 않습니다. 다음 항목을 함께 확인합니다.

- 저장소 소유자가 `SamsungSDSCloud` 같은 공식 조직인지
- Samsung SDS 공식 문서가 해당 GitHub 저장소를 배포처로 직접 연결하는지
- 설치 파일의 다운로드 도메인이 공식 문서 도메인인지
- 현재 사용하는 SCP 환경별 IAM endpoint를 지원하는지

`t2yijaeho/SCP-CLI`는 실제 CLI 사용법과 공식 문서 링크를 포함하고 있어 공식 가이드처럼 보이지만 개인 계정의 저장소입니다. 또한 개인 저장소에 포함된 구형 Java 바이너리를 설치하고 모든 환경에 공용 `openapi` 주소를 설정하도록 안내합니다. Enterprise 환경에서는 이 안내 대신 공식 문서 서버의 최신 `scp-cli`를 사용합니다.

## 환경별 IAM endpoint

| 환경 | CLI `auth_url` |
| --- | --- |
| Enterprise | `https://iam.e.samsungsdscloud.com/v1/endpoints` |
| Samsung 내부 | `https://iam.s.samsungsdscloud.com/v1/endpoints` |
| Sovereign | `https://iam.g.samsungsdscloud.com/v1/endpoints` |

Enterprise Console을 사용하는 경우 `e` 환경의 주소를 사용합니다.

## 1. 공식 CLI 여부 확인

```bash
command -v scp-cli
scp-cli --version
```

공식 CLI는 실행 파일 이름과 버전이 다음 형태로 확인됩니다.

```text
/usr/bin/scp-cli
scp-cli version v2.1.0
```

다음 특징의 별도 프로그램이 설치돼 있다면 구형 CMP CLI일 수 있으므로 Enterprise 작업에 사용하지 않습니다.

- 버전 출력에 `scp-tool-cli`가 표시됨
- Java 프로그램으로 실행됨
- `configure set cmp-url ...` 형태의 명령을 사용함
- 설정을 `~/.cmp`에 저장함

현재 설치된 파일을 바로 삭제하지 않습니다. 문제 발생 시 비교하거나 복원할 수 있도록 그대로 보존하고 새 공식 CLI를 별도 이름으로 설치합니다.

## 2. Enterprise 공식 CLI 설치

Samsung SDS Enterprise 공식 문서에서 Linux 바이너리를 내려받습니다.

```bash
mkdir -p "$HOME/.local/bin"
curl -fL \
  https://docs.e.samsungsdscloud.com/tools/cli/linux/scp-cli \
  -o "$HOME/.local/bin/scp-cli"
chmod 0755 "$HOME/.local/bin/scp-cli"
```

설치 결과를 확인합니다.

```bash
"$HOME/.local/bin/scp-cli" --version
```

출력 예시는 다음과 같습니다.

```text
scp-cli version v2.1.0
```

`~/.local/bin`이 `PATH`에 없다면 셸 설정에 추가합니다.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

계속 사용하려면 같은 내용을 `~/.bashrc`에 추가한 뒤 새 셸을 실행합니다.

## 3. Enterprise 인증 설정

공식 CLI는 `~/.scp/cli-config.json`을 사용합니다. 실제 Access Key와 Secret Key를 Git 저장소, README, 셸 스크립트에 기록하지 않습니다.

```bash
mkdir -p "$HOME/.scp"
chmod 0700 "$HOME/.scp"
```

`~/.scp/cli-config.json`을 다음 구조로 작성합니다.

```json
{
  "auth_url": "https://iam.e.samsungsdscloud.com/v1/endpoints",
  "access_key": "YOUR_ACCESS_KEY",
  "access_secret_key": "YOUR_SECRET_KEY",
  "default_scp_region": "kr-west1"
}
```

파일 권한을 제한합니다.

```bash
chmod 0600 "$HOME/.scp/cli-config.json"
```

키를 명령행 인자로 전달하면 셸 history나 프로세스 목록에 남을 수 있으므로 설정 파일을 사용하는 편이 안전합니다.

## 4. 인증 및 endpoint 검증

읽기 전용 Registry 목록 명령으로 인증을 확인합니다.

```bash
scp-cli scr registry list --format json
```

Registry가 없으면 출력이 비어 있을 수 있습니다. 오류 없이 종료되면 인증과 서비스 endpoint 탐색이 성공한 것입니다.

Enterprise 환경에서 Container Registry API는 다음과 같은 지역별 주소로 연결됩니다.

```text
https://scr.kr-west1.e.samsungsdscloud.com
```

다음 오류가 다시 발생한다면 현재 실행 중인 바이너리와 설정 경로를 확인합니다.

```text
Access key not found
```

```bash
command -v scp-cli
scp-cli --version
stat -c '%a %n' "$HOME/.scp/cli-config.json"
```

설정 파일 내용이나 `scp-cli --debug`, `--dry-run` 전체 결과는 공유하지 않습니다. 디버그 출력에는 Access Key, 서명 또는 요청 헤더가 포함될 수 있습니다.

## 5. Container Registry 생성

Registry 이름은 영문 소문자로 시작하고 영문 소문자와 숫자만 사용하며 길이는 3~25자여야 합니다. 하이픈은 사용할 수 없습니다.

```bash
REGISTRY_NAME="scloudtutorial01"
```

이름 중복 여부를 확인합니다.

```bash
scp-cli scr registry name-duplication show \
  --name "$REGISTRY_NAME" \
  --format json
```

`result`가 `false`이면 사용 중인 이름이 아니라는 의미입니다.

외부에서 인증 후 사용할 수 있는 비공개 Registry를 생성합니다.

```bash
REGISTRY_CREATE_OUTPUT=$(scp-cli scr registry create \
  --name "$REGISTRY_NAME" \
  --private_acl_enabled=false \
  --private_acl_resources='[]' \
  --public_acl_enabled=false \
  --public_acl_resources='[]' \
  --public_endpoint_enabled=true \
  --public_visible_enabled=false \
  --format json)

REGISTRY_ID=$(printf '%s' "$REGISTRY_CREATE_OUTPUT" | jq -r '.id')
test -n "$REGISTRY_ID"
test "$REGISTRY_ID" != null
```

이 설정의 의미는 다음과 같습니다.

- Public endpoint는 활성화하여 외부 네트워크에서 접근 가능
- Registry와 이미지는 익명 공개하지 않음
- 접근 시 SCP 인증 필요
- 별도의 public/private ACL 제한은 적용하지 않음

생성 요청 직후에는 `Creating` 상태가 반환됩니다.

```json
{
  "id": "REGISTRY_ID",
  "message": "Registry Successfully Created",
  "state": "Creating"
}
```

## 6. 생성 상태 확인

생성 응답에서 자동으로 추출한 ID를 사용합니다.

```bash
scp-cli scr registry show \
  --registry_id "$REGISTRY_ID" \
  --format json
```

정상적으로 완료되면 다음 항목을 확인합니다.

```text
state: Running
public_endpoint_enabled: true
public_visible_enabled: false
```

이름으로 목록을 조회할 수도 있습니다.

```bash
scp-cli scr registry list \
  --name "$REGISTRY_NAME" \
  --format json
```

## 7. 자주 발생하는 오류

### `PLATFORM-GW-00002: Access key not found`

구형 CMP CLI와 공용 `openapi` endpoint를 Enterprise 키와 함께 사용했는지 확인합니다. 키를 재발급하기 전에 공식 `scp-cli`, `~/.scp/cli-config.json`, `iam.e.../v1/endpoints` 조합인지 점검합니다.

### `400 Bad Request`

Registry 이름 규칙을 확인합니다.

```text
Registry name should be 3~25 characters (lower case, numbers) starting with English lower case.
```

올바른 예시는 다음과 같습니다.

```text
scloudtutorial01
```

잘못된 예시는 다음과 같습니다.

```text
scloud-tutorial-01
ScloudTutorial01
```

### 생성 후 계속 `Creating`으로 표시됨

Container Registry의 내부 Object Storage와 endpoint 프로비저닝에는 시간이 걸릴 수 있습니다. `Failed`가 아니라 `Creating`이면 잠시 후 `show` 명령을 다시 실행합니다.

## 8. Registry 삭제

더 이상 사용하지 않는 Registry는 과금 방지를 위해 삭제합니다. 삭제 전 Registry ID와 이름을 다시 확인합니다.

```bash
scp-cli scr registry show \
  --registry_id "$REGISTRY_ID" \
  --format json
```

삭제 명령의 최신 옵션은 help에서 확인합니다.

```bash
scp-cli scr registry delete --help
```

Registry 내부에 필요한 이미지가 없는지 확인한 뒤 삭제를 수행합니다.

## 최종 확인 목록

- `scp-cli --version`이 `scp-cli version v2.1.0`을 출력하는가
- `command -v scp-cli`가 공식 CLI를 가리키는가
- 설정 파일이 `~/.scp/cli-config.json`인가
- Enterprise `auth_url`이 `iam.e.../v1/endpoints`인가
- `scp-cli scr registry list`가 인증 오류 없이 실행되는가
- Registry가 `Running` 상태인가
- Public endpoint와 이미지 공개 설정이 의도한 값인가
