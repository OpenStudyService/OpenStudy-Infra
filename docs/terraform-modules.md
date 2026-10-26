# AWS Terraform 모듈 구성

관련 이슈: [#5](https://github.com/OpenStudyService/OpenStudy-Infra/issues/5).
DB 초기 적용 PR #4 위에 쌓은 후속 PR이다. #4를 먼저 병합한 뒤 이 변경을 병합한다.

## 변경 전

```text
terraform/aws/
├── main.tf           # 네트워크·EC2
├── configuration.tf  # 서버 설정
├── database.tf       # RDS·SQL 적용
├── ecs.tf            # ECS·ECR·앱 실행
├── frontend.tf       # EC2 정적 웹 배포
└── schedule.tf       # 시작·중지 스케줄
```

각 파일에서 리소스를 직접 선언했다. 기능 간 연결도 같은 폴더 안에서 참조했다.

## 변경 후

```text
terraform/aws/
├── main.tf       # 공통 값·템플릿·조회·파일 준비
├── modules.tf    # 기능별 모듈 연결
├── moved.tf      # 기존 리소스 주소 연결
├── variables.tf # 기존 입력값
└── outputs.tf   # 기존 출력값

terraform/modules/aws/
├── network/
├── server/
├── database/
├── applications/
├── frontend/
└── schedule/
```

| 모듈 | 담당 작업 |
| --- | --- |
| `network` | VPC·공개 서브넷·인터넷 연결·서버 보안 그룹 |
| `server` | EC2·서버 권한·SSM 설정·ECS 클러스터와 호스트 연결 |
| `database` | 비공개 DB 네트워크·RDS·SQL 게시와 SSM 적용 |
| `applications` | ECR·앱 실행 권한·ECS 태스크와 서비스 |
| `frontend` | EC2 정적 웹 배포용 S3·읽기 권한·게시 작업 |
| `schedule` | EC2·RDS 시작·중지 Lambda와 운영 스케줄 |

각 모듈은 `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`로 구성한다.
ECS 클러스터는 EC2가 처음 기동할 때 필요하므로 `server`에서 준비한다.
앱 이미지 저장소와 실제 앱 실행은 `applications`에서 관리한다.
Lambda 파일 압축은 공통 준비 단계에서 수행하고 결과를 `schedule`에 전달한다.

## 실행 방법과 기존 설정

실행 위치는 계속 `terraform/aws`이다. 모듈을 연결한 전체 구성을 같은 상태 파일로 관리한다.
기존 입력 35개와 출력 이름 19개를 유지한다. 기존 변수 파일과 예산 프로필을 계속 사용한다.
`terraform/cloudflare`와 선택형 `terraform/frontend`의 실행 구성은 유지한다.

모듈 경로가 추가됐으므로 계획을 만들기 전에 기존 위치에서 `terraform init`을 실행한다.
실제 적용 전 계획에서 리소스의 생성·수정·교체·삭제를 확인한다.
이번 작업은 실제 AWS 상태를 조회하거나 적용하지 않았다.

## 기존 리소스 연결

`moved.tf`에 55개 리소스 선언의 이전 주소와 새 주소를 기록한다.

| 리소스 | 이전 주소 | 새 주소 |
| --- | --- | --- |
| EC2 | `aws_instance.server` | `module.server.aws_instance.server` |
| RDS | `aws_db_instance.database[0]` | `module.database.aws_db_instance.database[0]` |
| VPC | `aws_vpc.main` | `module.network.aws_vpc.main` |
| ECS 서비스 | `aws_ecs_service.apps[0]` | `module.applications.aws_ecs_service.apps[0]` |

Terraform이 같은 리소스를 새 주소로 계속 관리하도록 연결한다.
기존 상태의 업그레이드를 지원하기 위해 `moved.tf`를 유지한다.
[Terraform 공식 설명](https://developer.hashicorp.com/terraform/language/block/moved)을 참고한다.

DB 모듈에는 서버 변경을 추적하는 `terraform_data.server_instance` 기록을 추가한다.
서버가 변경되면 DB 적용 작업도 다시 실행하는 기존 동작을 연결하기 위한 기록이다.
AWS 리소스나 비용을 추가하지 않는다. DB 마이그레이션이 켜진 경우에만 생성한다.

## 변경 전 상태로 검증

Terraform 1.16.6과 이전 소스가 있는 Git 커밋을 사용한다.

```sh
python3 scripts/check-terraform-module-moves.py \
  --base-ref 5998d73f36912145bad23e1d51287537ecebb2bf
```

검사는 이전 구성의 모의 상태를 만든 뒤 같은 상태로 새 모듈 구성을 계획한다.
과거 Terraform 구성과 현재의 같은 SQL·템플릿·웹 소스를 사용해 구성 구조의 차이를 비교한다.
실제 AWS 제공자 대신 모의 제공자를 사용한다.
이전 구성의 로컬 배포 명령은 검증용 사본에서 제거한다.
검증용 상태·사본·임시 테스트 파일은 종료 후 정리한다.

`live`와 `mock` 두 모드에서 주소 연결과 AWS 변경 여부를 확인한다.
이는 모의 계획 결과이다. 실제 AWS 조회 계획이나 실제 배포 검증으로 취급하지 않는다.

일반 기능 검사는 기존처럼 `./scripts/validate.sh`를 사용한다.
모듈 내부의 오류 차단 검사는 각 모듈의 테스트 폴더에서 함께 실행한다.
