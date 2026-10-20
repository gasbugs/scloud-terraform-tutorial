# SCP Container Registry 생성·업로드·정리 튜토리얼

이 문서는 Samsung Cloud Platform(SCP) Enterprise 환경에서 Container Registry를 생성하고, Docker Hub의 `hello-world` 이미지를 업로드한 뒤, Repository와 Registry를 순서대로 삭제하는 전체 생명주기를 설명합니다.

공식 기술 가이드의 흐름인 `Docker Hub pull → SCR login → tag → push`를 따릅니다. 실제 Access Key와 Secret Key는 문서, 셸 기록, Git 저장소에 넣지 않습니다.

## 1. 준비 상태 확인

다음 도구가 필요합니다.

- Enterprise 공식 `scp-cli` 2.x
- Docker Engine과 Docker CLI
- `jq`
- Container Registry 생성·조회·삭제 권한
- Registry 로그인과 이미지 pull/push 권한이 포함된 `ScrPullPushOnlyAccess` 정책

```bash
scp-cli --version
docker version
jq --version
```

Enterprise 공식 CLI는 `~/.scp/cli-config.json`을 사용합니다. 설정 파일의 구조와 설치 방법은 [Samsung Cloud Platform Enterprise CLI 설정 가이드](./SCLOUD_ENTERPRISE_CLI_GUIDE.md)를 먼저 확인합니다.

설정 파일에는 다음 항목이 있어야 합니다.

```json
{
  "auth_url": "https://iam.e.samsungsdscloud.com/v1/endpoints",
  "access_key": "YOUR_ACCESS_KEY",
  "access_secret_key": "YOUR_SECRET_KEY",
  "default_scp_region": "kr-west1"
}
```

파일 권한과 읽기 전용 API 호출로 준비 상태를 확인합니다. `scp-cli --debug`나 설정 파일 본문은 인증 정보가 노출될 수 있으므로 공유하지 않습니다.

```bash
stat -c '%a %n' "$HOME/.scp/cli-config.json"
scp-cli scr registry list --format json
```

설정 파일 권한은 `600`이어야 합니다. Registry가 하나도 없어도 목록 명령이 인증 오류 없이 끝나면 CLI와 IAM endpoint 조합은 정상입니다.

## 2. Registry 생성

Registry 이름은 영문 소문자로 시작하며 소문자와 숫자만 사용하고 길이는 3~25자여야 합니다. 하이픈은 사용할 수 없습니다.

```bash
REGISTRY_NAME="scloudtutorial01"

scp-cli scr registry name-duplication show \
  --name "$REGISTRY_NAME" \
  --format json
```

응답의 `result`가 `false`이면 같은 이름의 Registry가 없다는 뜻입니다. 다음 설정은 외부 Docker 환경에서 인증 후 사용할 수 있도록 public endpoint를 켜되, 이미지를 익명 공개하지 않습니다.

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

공식 `Create Registry 1.1` 응답의 최상위 `id`가 `REGISTRY_ID`에 자동으로 저장됩니다. 빈 값이나 `null`이면 다음 단계로 진행하지 않습니다. 생성 요청 직후에는 `Creating` 상태일 수 있습니다.

```bash
scp-cli scr registry show \
  --registry_id "$REGISTRY_ID" \
  --format json
```

`state`가 `Running`이 될 때까지 잠시 기다렸다가 조회 명령을 다시 실행합니다. `public_endpoint_enabled`는 `true`, 익명 공개를 나타내는 `public_visible_enabled`는 `false`인지 함께 확인합니다.

목록 명령에서 public domain을 얻어 변수로 저장합니다. 이 값은 credential이 아니므로 이미지 주소에 사용해도 됩니다.

```bash
REGISTRY_DOMAIN=$(scp-cli scr registry list \
  --name "$REGISTRY_NAME" \
  --format json | jq -r '.registries[0].public_domain')

test -n "$REGISTRY_DOMAIN"
printf '%s\n' "$REGISTRY_DOMAIN"
```

## 3. Repository 생성

Registry는 이미지를 저장하는 최상위 공간이고, Repository는 그 안에서 이미지들을 묶는 단위입니다. 이 예제에서는 `sample` Repository를 만들고 그 안에 `hello-world:v1` 이미지를 올립니다.

먼저 같은 이름의 Repository가 있는지 확인합니다.

```bash
REPOSITORY_NAME="sample"

scp-cli scr repository name-duplication show \
  --registry_id "$REGISTRY_ID" \
  --name "$REPOSITORY_NAME" \
  --format json
```

다음은 이미지 스캔·pull 차단·자동 삭제·잠금을 모두 비활성화한 실습용 설정입니다. `scp-cli v2.1`은 비활성화한 정책의 세부 값도 필수 인자로 받으므로 `High`, `90`, `*`를 함께 전달합니다.

```bash
REPOSITORY_CREATE_OUTPUT=$(scp-cli scr repository create \
  --registry_id "$REGISTRY_ID" \
  --name "$REPOSITORY_NAME" \
  --description "Docker Hub image upload tutorial" \
  --severity_limit High \
  --secret_excepted false \
  --scan_policy_enabled false \
  --language_excepted false \
  --fixed_version_excepted false \
  --auto_scan_enabled false \
  --vulnerable_image_pull_prevented false \
  --unscanned_image_pull_prevented false \
  --unmodified_excepted false \
  --locked false \
  --untagged_rule_enabled false \
  --untagged_rule_duration 90 \
  --outdated_rule_tag_expression '*' \
  --outdated_rule_enabled false \
  --outdated_rule_duration 90 \
  --lifecycle_policy_enabled false \
  --format json)

REPOSITORY_ID=$(printf '%s' "$REPOSITORY_CREATE_OUTPUT" | jq -r '.id')
test -n "$REPOSITORY_ID"
test "$REPOSITORY_ID" != null
```

생성된 Repository를 조회합니다.

```bash
scp-cli scr repository show \
  --repository_id "$REPOSITORY_ID" \
  --format json
```

응답의 이름이 `sample`이고 상태가 `Active`인지 확인합니다.

## 4. Docker Hub 이미지 준비

Docker Hub의 공식 `hello-world` 이미지를 내려받고 digest를 확인합니다.

```bash
docker pull hello-world:latest
docker image inspect hello-world:latest \
  --format 'Digest={{index .RepoDigests 0}} Size={{.Size}}'
```

이 튜토리얼에서 확인한 amd64 이미지 digest는 다음과 같았습니다. Docker Hub의 이미지 갱신이나 플랫폼 차이에 따라 값은 달라질 수 있습니다.

```text
hello-world@sha256:11a3eb1597e864c51b3f56733cb2e8a90bf0c284bfc05f9444d81c558bc848aa
```

## 5. SCR 로그인

공식 가이드에 따라 SCP Access Key를 Docker username으로, Secret Key를 password로 사용합니다. Secret Key는 명령행 인자로 넣지 않고 표준 입력으로 전달합니다.

로그인 전에 현재 사용자에게 `ScrPullPushOnlyAccess` 정책이 연결돼 있어야 합니다. 이 정책에는 다음 권한이 포함됩니다.

- `scr:LoginContainerRegistry`
- `scr:PullRepositoryImages`
- `scr:PushRepositoryImages`

실습용 Docker 인증 파일은 임시 디렉터리에만 저장합니다.

```bash
DOCKER_CONFIG_DIR=$(mktemp -d /tmp/scp-docker-config.XXXXXX)
chmod 0700 "$DOCKER_CONFIG_DIR"

jq -r '.access_secret_key' "$HOME/.scp/cli-config.json" | \
  DOCKER_CONFIG="$DOCKER_CONFIG_DIR" docker login "$REGISTRY_DOMAIN" \
    --username "$(jq -r '.access_key' "$HOME/.scp/cli-config.json")" \
    --password-stdin
```

정상이면 `Login Succeeded`가 출력됩니다. 이 단계에서 실패하면 아직 `tag`나 `push`를 실행하지 않습니다.

`unauthorized: authentication required`가 나오면 다음 항목을 확인합니다.

- 현재 Access Key가 Registry를 생성한 SCP 프로젝트의 키인지
- 사용자 또는 역할에 Registry·Repository push 권한이 있는지
- Registry의 public endpoint가 활성화됐는지
- `REGISTRY_DOMAIN`이 `*.scr.public.kr-west1.e.samsungsdscloud.com` 형태의 현재 Registry 주소인지
- CLI API 호출만 성공한 것을 Docker Registry push 권한까지 정상이라는 뜻으로 오해하지 않았는지

`no such host`가 나오면 credential 문제가 아니라 Docker daemon의 DNS 문제입니다. 호스트에서 다음 명령으로 public domain이 해석되는지 먼저 확인합니다.

```bash
getent hosts "$REGISTRY_DOMAIN"
curl -sS -o /dev/null -w '%{http_code}\n' \
  "https://$REGISTRY_DOMAIN/v2/"
```

인증 전 `/v2/` 요청의 `401`은 endpoint가 살아 있고 인증을 요구한다는 뜻입니다. 연결 시간 초과나 이름 해석 실패와 구분해야 합니다.

## 6. 이미지 태그와 push

SCP 공식 기술 가이드는 image reference를 `<SCR endpoint>/<Repository>/<Image>:<tag>` 형식으로 바꾼 뒤 push하도록 안내합니다. 이 예제의 Repository는 `sample`, 이미지 이름은 `hello-world`, tag는 `v1`입니다.

```bash
TARGET_IMAGE="$REGISTRY_DOMAIN/$REPOSITORY_NAME/hello-world:v1"

docker tag hello-world:latest "$TARGET_IMAGE"
docker image inspect "$TARGET_IMAGE" --format '{{json .RepoTags}}'
```

임시 인증 파일을 지정해 이미지를 push합니다.

```bash
DOCKER_CONFIG="$DOCKER_CONFIG_DIR" docker push "$TARGET_IMAGE"
```

push가 완료되면 마지막 줄의 digest를 기록합니다. 이 이미지 참조에서 `sample`은 앞 단계에서 만든 Repository이고, `hello-world`는 이미지 이름이며, `v1`은 tag입니다.

## 7. 업로드 결과 확인

Registry 아래의 Repository를 조회합니다.

```bash
scp-cli scr registry repository list \
  --registry_id "$REGISTRY_ID" \
  --name "$REPOSITORY_NAME" \
  --format json
```

응답의 `count`가 `1`이고 Repository 이름이 `sample`인지 확인합니다.

```bash
scp-cli scr repository image list \
  --repository_id "$REPOSITORY_ID" \
  --format json
```

이미지 목록에서 tag `v1`과 push가 반환한 digest가 일치하면 업로드 확인이 끝납니다. 단순히 `docker push`가 종료 코드 `0`이었다는 사실뿐 아니라 SCP 제어 API에서도 Repository와 이미지를 조회해야 최종 성공으로 판정합니다.

## 8. 임시 Docker 인증 정리

Registry 리소스를 삭제하기 전에 로컬 인증 파일과 추가 tag부터 정리합니다. `DOCKER_CONFIG_DIR`이 `/tmp/scp-docker-config.`로 시작하는 실습용 경로인지 확인한 뒤 삭제합니다.

```bash
docker image rm "$TARGET_IMAGE"
DOCKER_CONFIG="$DOCKER_CONFIG_DIR" docker logout "$REGISTRY_DOMAIN"
test -n "$DOCKER_CONFIG_DIR"
test "${DOCKER_CONFIG_DIR#/tmp/scp-docker-config.}" != "$DOCKER_CONFIG_DIR"
rm -rf -- "$DOCKER_CONFIG_DIR"
unset DOCKER_CONFIG_DIR TARGET_IMAGE
```

원본 `hello-world:latest`도 필요 없다면 별도로 삭제합니다.

```bash
docker image rm hello-world:latest
```

## 9. Repository 삭제

Repository를 삭제하면 그 안의 실습 이미지도 함께 제거되므로, ID와 이름을 다시 확인합니다. 특정 이미지만 삭제하려면 `scp-cli scr image delete`를 사용할 수 있지만 이 실습에서는 Repository 전체를 정리합니다.

```bash
scp-cli scr repository show \
  --repository_id "$REPOSITORY_ID" \
  --format json
```

다른 이미지가 없는 실습용 Repository가 맞으면 삭제합니다.

```bash
scp-cli scr repository delete \
  --repository_id "$REPOSITORY_ID" \
  --format json
```

Registry에서 Repository가 사라졌는지 확인합니다.

```bash
scp-cli scr registry repository list \
  --registry_id "$REGISTRY_ID" \
  --format json
```

실습 전용 Registry라면 `count`가 `0`이어야 합니다. 삭제가 비동기로 처리되는 경우 잠시 후 같은 조회 명령을 다시 실행합니다.

## 10. Registry 삭제

Registry 삭제는 내부 Repository가 비어 있는 것을 확인한 뒤 진행합니다.

```bash
scp-cli scr registry show \
  --registry_id "$REGISTRY_ID" \
  --format json
```

이름과 ID가 이 튜토리얼에서 만든 리소스와 일치하면 삭제합니다.

```bash
scp-cli scr registry delete \
  --registry_id "$REGISTRY_ID" \
  --format json
```

목록에서 Registry가 사라질 때까지 잠시 기다렸다가 다시 조회합니다.

```bash
scp-cli scr registry list \
  --name "$REGISTRY_NAME" \
  --format json
```

응답의 `count`가 `0`이면 SCP 리소스 정리가 완료된 것입니다.

```bash
unset REGISTRY_ID REGISTRY_NAME REGISTRY_DOMAIN REPOSITORY_ID REPOSITORY_NAME
```

## 11. 성공 판정표

| 단계 | 성공 증거 | 대표 실패 원인 |
| --- | --- | --- |
| Registry 생성 | `state`가 `Running` | 이름 규칙, IAM 권한, endpoint 오류 |
| Repository 생성 | 이름 `sample`, 상태 `Active` | 이름 중복, IAM 권한, 정책 옵션 오류 |
| endpoint 연결 | `/v2/`가 인증 전 `401` 반환 | DNS, timeout, public endpoint 비활성화 |
| Docker 로그인 | `Login Succeeded` | 다른 프로젝트의 키, push 권한 부족 |
| 이미지 push | `docker push`가 digest 반환 | 인증, DNS, Repository 권한 |
| SCP 조회 | Repository 1개와 `v1` tag 확인 | 비동기 반영 지연, 다른 Registry ID |
| Repository 정리 | Repository 목록 `count: 0` | 잘못된 ID, 삭제 진행 중 |
| Registry 정리 | Registry 목록 `count: 0` | 내부 Repository 잔존, 삭제 진행 중 |

## 참고 자료

- [Samsung Cloud Platform CLI Reference: Create Repository 1.1](https://docs.e.samsungsdscloud.com/clireference/container/scr/clis/createrepository/1.1/)
- [Samsung SDS 기술 가이드: Deploying Container Registry Image](https://cloud.samsungsds.com/serviceportal/sub/assets/pdf/en/SDS_Technical_Guide_Deployment_configuration_of_Container_Registry_Image_v1.0_en.pdf)
- [Samsung Cloud Platform Container Registry 소개](https://www.samsungsds.com/kr/container-containerregistry/containerregistry.html)
- [Docker login 문서](https://docs.docker.com/reference/cli/docker/login/)
