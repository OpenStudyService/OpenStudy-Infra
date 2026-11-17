# Terraform으로 AWS live 배포

Frontend·Backend를 기존 EC2에서 실행하고 비공개 RDS에 연결한다.
Frontend는 Nginx가 제공한다. Backend는 ECS의 단일 컨테이너다.

```mermaid
flowchart LR
    Browser[브라우저] -->|HTTPS 443| Nginx[EC2 Nginx · Frontend]
    Nginx -->|호스트 8081 → 컨테이너 8080| Backend[ECS Backend · prod]
    Backend -->|TLS 3306| RDS[비공개 MySQL RDS]
```

SSM은 서버 설정과 마이그레이션 실행에 사용한다. 서비스 요청과 DB 연결에 로컬 터널을 사용하지 않는다.
기존 EC2·RDS·운영 스케줄을 사용한다. ALB·NAT Gateway·CloudFront는 추가하지 않는다.

## 배포 준비

- Backend main의 깨끗한 소스로 AMD64 운영 이미지를 빌드하고 기존 ECR `service` 저장소에 게시한다.
- 태그는 소스 커밋으로 고정한다. `service_image`에는 ECR에서 확인한 SHA-256 다이제스트를 지정한다.
- DuckDNS 토큰은 `/openstudy-prod/duckdns/token`의 표준 SecureString으로 저장한다.
- 앱 DB 비밀번호는 `/openstudy-prod/apps/db-password`의 SecureString으로 유지한다.
- Infra SQL은 같은 Backend의 V1·V2 원본과 같아야 한다. 이미 적용한 SQL을 수정하지 않는다.

`aws-live.tfvars.json`은 Git에서 제외한다. 실제 비밀번호 대신 아래 설정과 SSM ARN을 넣는다.

| 설정 | 값 |
| --- | --- |
| `frontend_source_dir` | 검증한 Frontend 커밋의 깨끗한 작업 경로 |
| `enable_frontend`, `enable_duckdns` | `true` |
| `frontend_api_mode` | `live` |
| `apply_database_migrations` | `true` |
| `service_image` | 실제 Backend 이미지의 `repository@sha256:...` |
| `service_environment.DB_URL` | RDS 호스트:3306, `sslMode=VERIFY_IDENTITY`, `/app/rds-truststore.p12` |
| `service_environment.DB_USERNAME` | `openstudy_app` |
| `service_environment.TRUSTED_PROXIES` | 측정한 직접 상대 프록시 주소. 이번 배포는 `172.17.0.1/32` |
| `service_environment.SPRING_PROFILES_ACTIVE` | `prod` |
| `service_environment.SPRING_FLYWAY_ENABLED` | `false` |
| `service_secret_parameters.DB_PASSWORD` | 앱 비밀번호 SecureString ARN |

DB URL의 CA 저장소 설정은 Backend의 [운영 계약](https://github.com/OpenStudyService/OpenStudy-Backend/blob/main/docs/deployment/README.md#tls)을 따른다.
초대 이메일 발송은 별도 SMTP 설정 전까지 비활성으로 유지한다.

## Terraform 적용

실제 배포 설정이 있는 작업 브랜치에서 실행한다.
기존 리소스를 관리하던 state를 그대로 사용한다. 빈 state로 새 인프라를 생성하지 않는다.
별도 워크트리는 같은 state의 절대 경로로 초기화한다.

```sh
terraform -chdir=terraform/aws init -reconfigure -backend-config=path=/absolute/path/to/existing/terraform.tfstate
terraform -chdir=terraform/aws plan -var-file=profiles/budget.tfvars.example -var-file=aws-live.tfvars.json -out=aws-live.tfplan
terraform -chdir=terraform/aws apply aws-live.tfplan
```

계획에서 EC2와 RDS가 `no-op`인지 먼저 확인한다.
Frontend 빌드·검사·S3 게시·SSM 배포도 Terraform 적용 과정에서 실행한다.
다시 같은 계획 옵션으로 검사했을 때 `No changes`가 나와야 한다.

## 변경과 복구

Backend 교체는 이전 이미지 다이제스트로 새 계획을 만들고 적용한다.
ECS가 health 실패를 감지하면 배포를 실패로 처리한다.
앱 이미지 복구는 DB SQL을 되돌리지 않는다. 이미 적용한 SQL은 유지한다.
평일 11시 시작·매일 18시 중지와 18시 30분 중지 재시도 설정을 유지한다.

실제 배포 결과와 검증 범위는 [2026-10-30 기록](development-log/2026-10-30-aws-live-deployment.md)을 따른다.

## 직원 초대 SMTP

`invitation_smtp`를 설정하면 기존 Backend에 Gmail STARTTLS(587)를 연결한다.
`from_address`, `enabled`, `credentials_version`을 Git 제외 배포 변수에 지정한다.
초대 링크는 기존 DuckDNS 도메인의 `/invitations/accept`로 자동 생성한다.
계정·비밀번호는 Terraform `value_wo`와 ephemeral 입력으로 표준 SecureString에 저장한다.
ECS에는 `/apps/smtp-username`, `/apps/smtp-password`의 ARN만 전달한다.
계획·state에 실제 비밀번호를 저장하지 않는다. 계정을 변경할 때는 `credentials_version`을 올린다. 새 버전은 ECS 재배포도 유도해 새 값을 읽는다.

SMTP를 구성한 뒤에는 아래 도구로 계획과 적용을 실행한다.
이 도구는 env의 SMTP 자격증명 두 항목만 읽는다. 로컬 DB·프로필·관리자 설정을 반영하지 않는다.

```sh
python3 scripts/terraform-smtp.py --env-file /private/path/.env plan -var-file=profiles/budget.tfvars.example -var-file=aws-live.tfvars.json -out=smtp.tfplan
python3 scripts/terraform-smtp.py --env-file /private/path/.env apply smtp.tfplan
```

먼저 `enabled=false`로 SMTP 인증과 Backend 기동을 확인한다.
기존 시험용 대기 초대를 확인한 뒤 `enabled=true`로 다시 적용한다.
발송 대상 주소를 확인하고 초대를 생성한다. SMTP 접수와 DB 발송 상태를 확인한다.
시작 시 Gmail 인증을 검증한다. 반복 health 점검은 Gmail에 반복 로그인하지 않도록 메일 점검을 제외한다.
실제 발송 실패는 초대 발송 작업의 상태와 재시도에서 처리한다.

[Terraform 쓰기 전용 입력](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral)
