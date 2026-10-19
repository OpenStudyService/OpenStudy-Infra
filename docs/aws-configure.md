# AWS CLI 설정 순서

[README로 돌아가기](../README.md) · [구축 절차 2단계](setup.md#2-저장소와-aws-준비)

로컬 PC에서 IAM 액세스 키로 `aws configure`를 설정한다.
조직에서 SSO를 사용한다면 [SSO 설정 안내](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)를 따른다.

## 1. AWS CLI 설치 확인

```sh
aws --version
```

출력에 `aws-cli/2`가 있는지 확인한다.
명령을 찾을 수 없다면 [공식 설치 안내](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)를 따른다.

## 2. IAM 액세스 키 준비

사용 중인 IAM 액세스 키가 있다면 3단계로 이동한다.
새 키가 필요하면 다음 순서로 생성한다.

1. AWS 콘솔에서 **IAM → 사용자 → 사용할 사용자**로 이동한다.
2. **보안 자격 증명 → 액세스 키 → 액세스 키 만들기**를 선택한다.
3. 사용 목적 안내를 확인하고 키를 생성한다.
4. `Access key ID`와 `Secret access key`를 보관한다.

Secret access key는 생성할 때만 확인할 수 있다.
키는 Git과 채팅에 기록하지 않는다. [공식 액세스 키 안내](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-keys-admin-managed.html)를 참고한다.

## 3. aws configure 입력

```sh
aws configure
```

다음 네 항목을 순서대로 입력한다.

| 입력 항목 | 입력값 |
| --- | --- |
| AWS Access Key ID | 2단계의 Access key ID |
| AWS Secret Access Key | 2단계의 Secret access key |
| Default region name | `ap-northeast-2` |
| Default output format | `json` |

키는 로컬 `~/.aws/credentials`에 저장한다. 리전과 출력 형식은 `~/.aws/config`에 저장한다.
기존 값을 유지하려면 해당 항목에서 Enter를 누른다. [공식 configure 안내](https://docs.aws.amazon.com/cli/latest/reference/configure/)를 따른다.

## 4. 인증 확인 후 구축 재개

```sh
aws sts get-caller-identity --query Account --output text
```

대상 AWS 계정의 12자리 ID가 나오면 인증에 성공한 상태다.
이 값을 `terraform/aws/terraform.tfvars`의 `aws_account_id`에 입력한다.
이후 [구축 절차 3단계](setup.md#3-terraform-변수-설정)부터 진행한다.
인증 확인 명령은 [STS 공식 안내](https://docs.aws.amazon.com/cli/latest/reference/sts/get-caller-identity.html)를 따른다.

## 오류가 발생하면

| 오류 | 확인할 내용 |
| --- | --- |
| `Unable to locate credentials` | `aws configure`에 키를 입력했는지 확인한다. |
| `InvalidClientTokenId` | 키의 활성 상태와 입력한 키 쌍을 확인한다. |
| Terraform의 `AccessDenied` | 해당 리소스 작업에 필요한 IAM 권한을 확인한다. 인증 성공과 생성 권한은 별개다. |

계속 이전 키를 사용한다면 `aws configure list`로 적용된 설정 출처를 확인한다.
환경변수의 자격증명은 파일보다 우선한다. [설정 우선순위](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html#configure-precedence)를 따른다.
