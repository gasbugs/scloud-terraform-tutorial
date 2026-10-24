# Samsung Cloud Platform Terraform SSH VM 튜토리얼

이 프로젝트는 Samsung Cloud Platform(SCP) Enterprise 환경에 Ubuntu 24.04 Virtual Server 한 대와 SSH 접속에 필요한 네트워크를 Terraform으로 구성하는 실습입니다. 생성부터 접속 확인, outbound 통신 확인, 전체 삭제까지 한 디렉터리에서 수행합니다.

SCP Container Registry의 생성부터 Docker Hub 이미지 업로드와 전체 정리까지는 [SCP Container Registry 생성·업로드·정리 튜토리얼](./SCLOUD_CONTAINER_REGISTRY_TUTORIAL.md)을 참고합니다.

한국어 뉴스 분류 모델의 학습 전후 비교는 [Simple AI Training 실습](docs/ynat-training-job-guide.md)을 참고합니다. `git clone`부터 시작해 File Storage에 코드·데이터를 업로드하고 Training Job을 실행합니다. File Storage 생성의 `Bad Request`는 현재 미해결이며 가이드에 표시되어 있습니다.

## 프로젝트가 만드는 리소스

- `10.10.0.0/16` VPC와 `10.10.1.0/24` General Subnet
- Firewall을 사용하는 Internet Gateway(`IGW`)와 Public IP
- Ubuntu 24.04 Virtual Server, 16 GiB SSD boot volume
- Standard V3 최소 타입 `s3v1m2`(1 vCPU, 2 GiB)
- SCP Key Pair와 권한 `0600`의 로컬 private key
- 현재 공인 IP `/32`에서 들어오는 TCP 22만 허용하는 Firewall 및 Security Group 규칙
- 외부로 나가는 모든 IPv4를 허용하는 Firewall 및 Security Group 규칙

Inbound SSH는 지정한 공인 IP 하나로 제한하지만 outbound는 `0.0.0.0/0`, 모든 프로토콜을 허용합니다. 운영 환경에서는 DNS, HTTP, HTTPS처럼 필요한 통신만 허용하도록 축소하는 것이 좋습니다.

## 1. 실행 전 준비

다음 도구와 권한이 필요합니다.

- Terraform 1.13 이상 2.0 미만
- 공식 `scp-cli` v2.1과 `jq`
- VPC, Subnet, Internet Gateway, Firewall Rule, Security Group, Public IP, Key Pair, Virtual Server 생성·삭제 권한

```bash
terraform version
scp-cli --version
jq --version
```

이 프로젝트는 `SamsungSDSCloud/samsungcloudplatformv2` 5.2 계열과 `hashicorp/local` 2.5 계열을 사용합니다.

## 2. SCP 환경에 맞는 IAM 주소 선택

SCP Console 분기 페이지 `https://cloud.samsungsds.com/serviceportal/console_branch.html`의 `cloud.*` 분기는 Enterprise 환경입니다.

| 환경 | Terraform `auth-url` |
| --- | --- |
| Enterprise | `https://iam.e.samsungsdscloud.com/v1` |
| Samsung 내부 | `https://iam.s.samsungsdscloud.com/v1` |
| Sovereign | `https://iam.g.samsungsdscloud.com/v1` |

Enterprise 사용자가 `iam.s...`를 지정하면 `/v1/endpoints` 연결에서 timeout이 발생할 수 있습니다. 가정용 공유기 방화벽이 아니라 잘못된 환경의 IAM endpoint를 선택한 문제일 수 있습니다.

```bash
curl --connect-timeout 5 -I https://iam.e.samsungsdscloud.com/v1/endpoints
```

HTTP 오류가 반환되더라도 TCP와 TLS 연결은 된 것입니다. `connect: connection timed out`이면 Terraform 실행 전에 환경과 endpoint부터 다시 확인합니다.

## 3. scp-cli 기본 설정

Enterprise 환경에서는 공식 `scp-cli`와 `~/.scp/cli-config.json`을 사용합니다. 구형 CMP CLI의 `~/.cmp`, `configure set`, `openapi.samsungsdscloud.com` 설정은 사용하지 않습니다. 설치와 공식 배포처 확인은 [Samsung Cloud Platform Enterprise CLI 설정 가이드](./SCLOUD_ENTERPRISE_CLI_GUIDE.md)를 참고합니다.

SCP Console에서 Authentication Key를 발급한 뒤 다음 구조로 설정합니다. 실제 credential을 README나 셸 스크립트에 저장하지 않습니다.

```json
{
  "auth_url": "https://iam.e.samsungsdscloud.com/v1/endpoints",
  "access_key": "YOUR_ACCESS_KEY",
  "access_secret_key": "YOUR_SECRET_KEY",
  "default_scp_region": "kr-west1"
}
```

```bash
chmod 0600 "$HOME/.scp/cli-config.json"
scp-cli scr registry list --format json
```

목록 조회가 인증 오류 없이 끝나면 CLI 설정이 정상입니다. 설정 파일 본문과 `--debug` 출력에는 credential이나 서명이 포함될 수 있으므로 공유하지 않습니다.

## 4. scp-cli 설정을 Terraform 형식으로 동기화

CLI와 Terraform provider는 서로 다른 설정 저장소를 사용합니다.

```text
scp-cli                           ~/.scp/cli-config.json
samsungcloudplatformv2 provider  ~/.scpconf/config.json
                                 ~/.scpconf/credentials.json
```

동기화 스크립트로 공식 CLI 설정을 Terraform 형식으로 변환합니다. CLI의 `/v1/endpoints` 주소는 Provider가 요구하는 `/v1` 기준 주소로 자동 변환됩니다.

```bash
./scripts/sync-scp-cli-terraform-config.sh
```

스크립트는 credential을 화면에 표시하지 않습니다. `.scpconf`에는 `0700`, JSON 파일에는 `0600`을 적용하며 기존 파일은 timestamp가 붙은 백업으로 보존합니다. 다른 설정 파일은 `--source-file FILE`로 선택합니다.

## 5. Terraform 입력값 작성

```bash
cp terraform.tfvars.example terraform.tfvars
curl -4 https://checkip.amazonaws.com
```

공인 IP 출력이 `198.51.100.24`라면 다음과 같이 작성합니다.

```hcl
zone                 = "kr-west1-b"
ssh_allowed_cidr     = "198.51.100.24/32"
private_key_filename = "./tf-ssh.pem"

ubuntu_image_id = "YOUR_UBUNTU_24_04_STANDARD_IMAGE_ID"
gateway_type    = "IGW"
```

`ssh_allowed_cidr`는 반드시 단일 IPv4를 뜻하는 `/32`여야 합니다. 더 넓은 CIDR은 validation에서 거부됩니다.

### Ubuntu 24.04 Image ID

Image ID는 service zone에 따라 달라질 수 있으므로 SCP Console의 Standard Image 목록에서 확인합니다. Enterprise `kr-west1`에서 이번에 검증한 값은 다음과 같습니다.

```hcl
ubuntu_image_id = "b8cd519a-c8ce-4a51-ac8d-aab9888339bc"
```

다른 계정이나 service zone에서는 Console 조회 결과로 교체합니다. live image data source는 매 plan을 SCP API 연결 상태에 종속시키지 않기 위해 사용하지 않습니다.

### Server Type과 zone

기본 Server Type은 `s3v1m2`입니다. 검증한 환경에서는 이 타입이 `kr-west1-b`에만 제공됐습니다. `kr-west1-a`를 사용하면 다음 오류가 발생합니다.

```text
Server Type 's3v1m2' zones '['kr-west1-b']' don't include the server zone 'kr-west1-a'.
```

다른 zone을 사용하려면 그 zone이 지원하는 타입을 지정합니다.

```hcl
server_type_id = "SERVER_TYPE_AVAILABLE_IN_YOUR_ZONE"
```

## 6. 초기화와 검증

```bash
terraform init
terraform fmt -check
terraform validate
```

```text
Success! The configuration is valid.
```

`Missing samsungcloudplatformv2 Auth URL`, `Access Key`, `Secret Key`가 나오면 4단계 동기화를 다시 확인합니다. AWS의 `default` 프로필은 이 provider 인증에 사용되지 않습니다.

## 7. 실행 계획 검토

```bash
terraform plan -out=tfplan
```

최초 실행은 다음 형태입니다.

```text
Plan: 12 to add, 0 to change, 0 to destroy.
```

다음 항목을 확인합니다.

- Gateway와 Public IP type이 `IGW`인지
- VM zone이 Server Type을 지원하는지
- `image_id`가 실제 Ubuntu 24.04 Image ID인지
- SSH source가 자신의 공인 IP `/32`인지
- inbound는 TCP 22만, outbound는 `0.0.0.0/0`의 `ALL`인지

계획 파일에는 민감한 값이 포함될 수 있으므로 Git에 commit하지 않습니다.

## 8. 리소스 생성

```bash
terraform apply tfplan
```

Subnet과 VM은 provisioning 중 수 분간 `Still creating...`이 출력될 수 있습니다. 이번 검증에서는 Subnet 약 7분, VM 약 2분이 걸렸습니다. API 연결 오류 없이 resource ID를 polling 중이라면 완료될 때까지 기다립니다.

```text
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

## 9. 출력과 drift 확인

```bash
terraform output
terraform output -raw ssh_command
stat -c '%a %n' ./tf-ssh.pem
terraform plan -detailed-exitcode
```

private key는 다음 권한이어야 합니다.

```text
600 ./tf-ssh.pem
```

구성과 실제 리소스가 일치하면 plan은 종료 코드 `0`과 함께 다음을 출력합니다.

```text
No changes. Your infrastructure matches the configuration.
```

Security Group protocol은 API가 소문자 `tcp`로 반환하므로 코드도 소문자를 사용합니다. 대문자 `TCP`는 매 plan에서 drift를 만들고 `Update not supported`를 유발합니다. Firewall의 `ALL` 서비스도 `service_value = "ALL"`을 함께 지정해야 drift가 남지 않습니다.

## 10. SSH 접속과 outbound 확인

```bash
ssh -i ./tf-ssh.pem ubuntu@PUBLIC_IP
```

접속 후 IP와 DNS·HTTPS 통신을 각각 확인합니다.

```bash
ping -c 4 8.8.8.8
curl -I https://example.com
```

둘 다 실패하면 Security Group egress와 Internet Gateway Firewall outbound를 함께 확인합니다. 이 프로젝트는 두 계층 모두에서 전체 IPv4 outbound를 허용합니다. `ping`만 실패하고 HTTPS가 성공한다면 외부 대상이 ICMP를 차단한 경우일 수 있습니다.

공인 IP가 바뀌면 `ssh_allowed_cidr`를 수정하고 다시 적용합니다.

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

## 11. 전체 리소스 삭제

VM과 Public IP는 비용이 발생할 수 있습니다. 삭제 계획에 이 프로젝트의 리소스만 포함됐는지 검토합니다.

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

`local_sensitive_file`도 관리 대상이므로 `tf-ssh.pem`이 함께 삭제됩니다. 정리가 끝났는지 확인합니다.

```bash
terraform state list
test ! -e ./tf-ssh.pem
```

state 명령이 아무것도 출력하지 않고 `test`가 종료 코드 `0`이면 완료입니다.

## 오류별 원인과 조치

### `Missing samsungcloudplatformv2 Auth URL`

Provider가 `~/.scpconf`를 읽지 못한 상태입니다. `scp-cli`와 Terraform Provider의 기본 설정 경로가 다르므로 동기화 스크립트를 실행합니다.

### `iam.s.../v1/endpoints: connect: connection timed out`

Enterprise 계정에 Samsung 내부용 endpoint를 사용한 경우입니다.

```bash
./scripts/sync-scp-cli-terraform-config.sh \
  --auth-url https://iam.e.samsungsdscloud.com/v1 \
  --region kr-west1
```

### Image data source가 계속 `Still reading...`

인증 또는 SCP API 연결이 끝나지 않은 상태입니다. 현재 구성은 live image lookup을 사용하지 않으므로 실제 ID가 `ubuntu_image_id`에 들어 있는지 확인합니다.

### `Access key not found`

CLI 프로필의 키가 해당 SCP 환경에서 유효하지 않습니다. 올바른 환경에서 키를 재발급하고 CLI 설정과 동기화를 다시 수행합니다.

### Server Type이 zone을 지원하지 않음

기본 `s3v1m2`는 검증 환경에서 `kr-west1-b`를 요구했습니다. zone 또는 Server Type ID를 함께 조정합니다.

### Security Group rule에서 `Update not supported`

`protocol = "TCP"`처럼 API 반환값과 대소문자가 다른지 확인합니다. 이 프로젝트는 `protocol = "tcp"`를 사용합니다.

## 보안 주의사항

- Access Key와 Secret Key를 `.tf`, `terraform.tfvars`, README에 기록하지 않습니다.
- `~/.scp/cli-config.json` 본문과 `scp-cli --debug` 출력은 credential이 포함될 수 있으므로 공유하지 않습니다.
- private key와 Terraform state를 같은 수준으로 보호합니다.
- SSH 22번을 `0.0.0.0/0`에 개방하지 않습니다.
- `terraform.tfvars`, state, saved plan과 PEM 파일을 Git에 commit하지 않습니다.
- 전체 outbound 허용은 실습용입니다. 운영 환경에서는 최소 권한으로 제한합니다.
