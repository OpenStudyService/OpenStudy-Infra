# AWS MySQL과 테이블 배포

[README로 돌아가기](../README.md)

## 구성

네트워크와 서비스 배치는 [최신 AWS 아키텍처](deployment.md#1-aws-배치도)를 따른다.
기본 DB 한 대를 EC2와 같은 AZ에 둔다. 대기 DB는 생성하지 않는다.

`terraform/aws`에서 `enable_database = true`를 설정하면 RDS와 테이블을 함께 생성한다.
기본값은 `false`다. 기존 웹 배포만 실행할 때는 DB를 생성하지 않는다.

- RDS MySQL 8.4.11, `db.t4g.micro`, 암호화한 gp3 20GiB를 사용한다.
- `multi_az = false`로 Single-AZ Primary 한 대를 생성한다.
- 서로 다른 가용 영역의 비공개 서브넷 두 개를 사용한다. 인터넷 경로와 공인 IP는 없다.
- 두 번째 AZ의 서브넷은 RDS 서브넷 그룹의 요구조건이다. 해당 서브넷에 DB를 생성하지 않는다.
- EC2와 Flyway는 Primary의 RDS 엔드포인트를 사용한다.
- TCP 3306 접속은 기존 EC2의 보안 그룹에서만 허용한다.
- RDS가 관리자 비밀번호를 생성하고 Secrets Manager에서 관리한다.
- Terraform은 비밀번호 값을 조회하지 않는다. state에는 비밀번호가 들어가지 않는다.
- 저장 시간과 DB 세션 시간대는 UTC다. 화면의 영업일 계산은 애플리케이션에서 서울 시간으로 처리한다.
- 연결은 TLS를 사용한다. Flyway는 AWS CA와 DB 호스트 이름을 검사한다.
- 현재 예산 프로필은 사용자 요청으로 자동 백업과 삭제 시 최종 스냅샷을 만들지 않는다.
- `database_backup_retention_days=0`, `database_skip_final_snapshot=true`를 사용한다. 삭제 보호는 유지한다.
- 프로젝트 기본값도 자동 백업 0일·최종 스냅샷 생략이다. 보관 기간에는 0~35일을 지정할 수 있다.
- 예산 프로필의 `database_apply_immediately=true`는 승인한 DB 변경을 유지보수 시간까지 기다리지 않고 적용한다.
- DB 패치 버전은 고정한다. 업그레이드할 때는 `database_engine_version`을 바꾸고 새 계획을 적용한다.

DB 인스턴스 한 대의 실행 시간과 저장 공간을 과금한다. 중지 시간에도 저장 공간·백업·Secrets Manager 비용은 발생한다.
평일 11:00~18:00 운영은 [ECS 예산 구성](ecs-budget.md)의 스케줄을 사용한다.
기존 EC2의 계정 혜택 확인이 RDS 무료 사용을 보장하지 않는다.
지원 버전과 인스턴스 종류는 AWS 리전에 따라 달라진다.

## 적용 순서

저장소 루트에서 실행한다. Terraform 1.16.6과 기존 AWS 인증을 사용한다.
기존 `terraform/aws/terraform.tfvars`에 다음 설정을 추가한다.
이 파일은 Git에서 제외한다. DB 비밀번호는 입력하지 않는다.

```hcl
enable_database           = true
apply_database_migrations = true
database_name             = "openstudy"
database_engine_version   = "8.4.11"
database_instance_class   = "db.t4g.micro"
database_storage_gib      = 20
database_backup_retention_days = 0
database_skip_final_snapshot = true
database_apply_immediately = true
```

```sh
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws validate
terraform -chdir=terraform/aws plan -out=database.tfplan
terraform -chdir=terraform/aws apply database.tfplan
```

계획에서 `multi_az = false`와 Primary 한 대를 확인한다.
`enable_frontend = true`인 구성은 기존 Frontend 빌드 실행 환경도 필요하다.
Single-AZ RDS 준비가 끝나면 SSM이 EC2에서 Flyway를 실행한다. Terraform은 최대 30분 동안 성공을 기다린다.
테이블 생성만 실패하면 DB는 남는다. 오류를 확인하고 새 계획을 적용한다.

스키마 적용을 나중에 실행하려면 `apply_database_migrations = false`로 DB만 생성한다.
이 값을 `true`로 바꾸고 다시 적용하면 테이블을 생성한다.
DB를 끄는 `enable_database = false`는 기존 DB의 삭제를 뜻한다.

## SQL 관리

첨부한 v0.5 초안을 `database/migrations/V1__initial_schema.sql`에 저장했다.
업무용 테이블 58개를 포함한다. 계정과 초기 업무 데이터는 넣지 않는다.
Flyway가 별도로 `flyway_schema_history` 테이블을 생성한다.

Terraform이 SQL과 실행 스크립트를 전용 비공개 S3 버킷에 게시한다.
파일 해시가 바뀌면 새 SSM 문서 버전을 적용한다.
SSM은 다운로드한 파일의 SHA-256을 확인한다.
EC2는 실행 시점에만 Secrets Manager에서 관리자 정보를 읽는다.
비밀번호를 포함한 임시 설정은 `/run`에 권한 600으로 만들고 실행 종료 시 삭제한다.
SSM 문서와 Terraform 출력에는 비밀번호가 없다.

Flyway 11.20.2와 JDBC 드라이버 3.5.9를 고정하고 SHA-256을 검사한다.
EC2에 Amazon Corretto 21을 설치하고 해당 CPU의 Java를 사용한다.
다운로드 파일에 포함된 x86 JRE와 불필요한 DB 드라이버는 설치하지 않는다.
처음 실행할 때는 공식 배포 파일을 받기 위한 EC2의 인터넷 연결이 필요하다.

한 번 적용한 V1은 수정하지 않는다.
변경은 `V2__add_task_index.sql`처럼 새 파일로 추가한다.
파일명은 숫자 버전과 영문·숫자·밑줄 설명을 사용한다.
같은 스키마를 Backend에서도 관리한다면 이 파일과 Flyway 이력을 함께 인계한다.
Backend의 Hibernate 자동 테이블 생성은 사용하지 않는다.

### 빈 DB에 V1~V3 처음 적용

현재 배포 SQL은 기존 V1과 Backend에서 가져온 V2·V3이다.
파일 원본과 실행 담당은 [SQL 안내](../database/migrations/README.md)에 기록한다.
기존 RDS의 대상 DB가 비어 있으면 같은 RDS에 세 파일을 순서대로 적용한다.
버전마다 RDS를 새로 만들지 않는다. V3만 단독으로 실행하지 않는다.

Terraform은 세 SQL과 실행 스크립트를 S3에 올리고 기존 EC2의 SSM 작업에서 Flyway를 실행한다.
초기 적용 후 업무·세션 테이블 65개와 `flyway_schema_history` 1개가 생긴다.
이력에는 V1·V2·V3 성공이 남는다. 같은 설정으로 다시 실행하면 추가 적용은 0건이다.
Backend는 `SPRING_FLYWAY_ENABLED=false`, Hibernate `ddl-auto=validate`로 기동한다.
Infra가 적용하는 동안 Service의 Flyway를 켜거나 설정을 시크릿으로 덮어쓰면 Terraform이 중단한다.

실제 적용 전 빈 DB인지 확인한다. 기존 테이블이나 데이터가 발견되면 적용을 멈추고 별도 업그레이드 절차를 따른다.
과거 V1 적용 기록을 현재 RDS 상태로 간주하지 않는다.
사용자가 확인한 현재 RDS는 빈 상태이며, 이 변경에서 실제 RDS 조회나 적용은 수행하지 않는다.

이미 적용한 파일을 바꾸면 Flyway가 중단한다.
자동 `clean`, `repair`, 기존 스키마의 자동 `baseline`은 실행하지 않는다.
MySQL DDL은 전체 파일 단위로 되돌릴 수 없다.
중간 실패 시 생성된 테이블과 Flyway 이력을 확인한 뒤 복구한다.
사용 중인 DB에 V1을 수동으로 다시 실행하지 않는다.

## 결과 확인

```sh
terraform -chdir=terraform/aws output database_endpoint
terraform -chdir=terraform/aws output database_name
terraform -chdir=terraform/aws output database_multi_az
terraform -chdir=terraform/aws output database_master_secret_arn
terraform -chdir=terraform/aws output database_migration_association_id
```

`database_multi_az` 출력은 `false`여야 한다.
마지막 출력의 연결 ID로 AWS Systems Manager의 State Manager 실행 결과를 확인한다.
V1~V3 초기 적용에 성공한 뒤 업무·세션 테이블 65개와 Flyway 이력 테이블 1개가 있어야 한다.
`flyway_schema_history`의 버전 1·2·3이 모두 성공인지 확인한다.
같은 파일로 다시 실행하면 SQL을 재적용하지 않는다.
DB 주소는 비공개 주소다. 로컬 PC에서 바로 접속할 수 없다.
자동으로 전환할 대기 DB는 없다. 장애 시 복구 시간이 필요하다.
애플리케이션용 제한 권한 계정과 Backend 연결은 별도 작업이다.
기존 웹의 테스트 로그인과 브라우저 저장 방식은 이 작업으로 변경하지 않는다.

## 검증

AWS 리소스를 만들지 않는 검증은 다음과 같다.

```sh
terraform -chdir=terraform/aws test
python3 -m unittest discover -s tests -p 'test_migrate_database.py' -v
```

Docker와 OpenSSL이 있는 환경에서 실제 스키마를 검사할 수 있다.
공식 MySQL·Java 이미지와 Flyway 파일을 내려받는다.
임시 DB는 외부 포트를 열지 않는다. 내부 전용 Docker 네트워크와 메모리 볼륨을 사용한다.
검증 종료 시 테스트 컨테이너와 네트워크를 삭제한다. 내려받은 Docker 이미지는 남는다.

```sh
python3 scripts/check-database.py
```

이 검증은 빈 DB의 V1~V3 적용·이력·테이블 생성, Flyway validate, TLS 인증서·호스트 이름 검사, 두 번째 적용의 무변경과 V1 변경 거부를 확인한다.
Backend의 실행 JAR을 준비하면 같은 임시 DB에 연결해 Hibernate validate와 서버 기동도 확인할 수 있다.
Java 21의 `keytool`이 필요하다. 임시 DB에만 적용하는 테스트용 인증서를 사용한다.

```sh
python3 scripts/check-database.py --backend-jar /absolute/path/to/backend.jar
```

Backend 검증은 Flyway를 끈 상태로 실행한다. 사용자 DB에 접속하거나 포트를 외부에 공개하지 않는다.
RDS의 실제 생성과 SSM 전체 실행 검증은 별도의 AWS 적용이 필요하다.

2026-10-21에 ARM64 EC2의 격리된 임시 MySQL 8.4.11에서 위 검증을 통과했다.
업무용 테이블 58개와 Flyway 이력 테이블 1개를 생성했다.
Terraform 모의 테스트 20개와 Python 테스트 34개도 통과했다.
DB 활성화 계획은 추가 18개, 기존 리소스 변경·삭제 0개다.
이 검증에서 실제 RDS는 생성하지 않았다.

이후 같은 날 요청을 반영해 Single-AZ Primary 한 대로 변경했다.
과거 Multi-AZ 계획은 폐기한다. 현재 변수와 예산 프로필로 계획을 다시 생성한다.
실제 RDS 생성과 ECS 앱의 DB 연결은 아직 검증하지 않았다.

ECS Service의 기본값은 `SPRING_FLYWAY_ENABLED=false`다. Infra가 SQL을 관리한다.
Backend의 다른 V1 파일과 기존 Flyway 이력을 섞지 않는다.
Backend로 소유권을 넘길 때는 먼저 V1 파일 이름·설명·원문과 실제 Flyway 이력을 대조한다.
Infra의 V1 이름은 `V1__initial_schema.sql`이고 Backend는 `V1__init_schema.sql`이다.
현재는 Infra가 실행하므로 Backend의 Flyway는 끈다. 파일 SHA-256과 Flyway checksum을 같은 값으로 취급하지 않는다.
그다음 `apply_database_migrations=false`와 앱 Flyway 설정을 함께 변경한다.
기존 V1 체크섬을 자동 repair로 덮어쓰지 않는다.

## 삭제

DB를 삭제할 때는 먼저 `database_deletion_protection = false`를 설정하고 적용한다.
현재 예산 프로필은 `database_skip_final_snapshot=true`라 최종 백업을 만들지 않는다.
별도로 최종 백업을 켜려면 이 값을 `false`로 바꾸고 `database_final_snapshot_identifier`에 아직 없는 이름을 지정한다.
그다음 전체 삭제 계획을 확인하고 적용한다.

```sh
terraform -chdir=terraform/aws plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/aws apply destroy.tfplan
```

DB와 RDS가 관리하는 관리자 시크릿, 마이그레이션용 S3 버킷을 삭제한다.
최종 스냅샷을 사용한 구성에서는 해당 스냅샷이 남는다. 현재 예산 프로필은 생성하지 않는다.
이전에 별도로 만든 스냅샷도 전체 정리 범위에서 확인한다.
최종 백업 없이 삭제할 때만 `database_skip_final_snapshot = true`를 설정하고 먼저 적용한다.
수동으로 만든 스냅샷과 AWS Backup 복구 지점은 Terraform 삭제 대상에 포함되지 않는다.

## 공식 자료

- [RDS의 비공개 네트워크와 서브넷](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html)
- [RDS 관리 비밀번호와 Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [RDS MySQL의 TLS 연결](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql-ssl-connections.html)
- [Flyway MySQL 드라이버](https://documentation.red-gate.com/flyway/reference/database-driver-reference/mysql)
- [JDBC 인증서와 호스트 이름 검사](https://mariadb.com/docs/connectors/mariadb-connector-j/using-tls-ssl-with-mariadb-java-connector)


## 2026-10-22 실제 RDS 검증

서울 리전의 `openstudy-prod-mysql`을 실제 생성했다.
MySQL 8.4.11·db.t4g.micro·Single-AZ·gp3 20GiB를 사용한다.
EC2와 같은 `ap-northeast-2b`에 배치했다. 공인 접속은 비활성화했다.
최초 배포 당시에는 계정 제한으로 자동 백업 1일과 최종 스냅샷을 사용했다.
이후 같은 날 사용자 요청으로 두 백업을 끄는 변경을 적용했다. 삭제 보호는 유지한다.
SSM 마이그레이션 연결 `218b4b57-3998-41b2-9e04-b67977a0a17c`는 성공했다.
EC2에서 AWS CA와 호스트 이름을 검사한 TLS 연결로 다음 값을 조회했다.

```text
total_tables=59, business_tables=58
version=1, success=1
require_secure_transport=1, time_zone=UTC
Ssl_cipher=TLS_AES_256_GCM_SHA384
```

관리자 비밀번호는 서버 메모리에서만 사용했다. 조회 결과와 Git에는 넣지 않았다.
최종 Terraform 계획은 예산 프로필 기준 `No changes`다.

### 같은 날 백업 비활성화 검증

사용자 요청으로 자동 백업과 삭제 시 최종 스냅샷을 껐다.
현재 기본값과 예산 프로필은 `database_backup_retention_days=0`, `database_skip_final_snapshot=true`다.
RDS 재시작 후 available 상태와 자동 백업 보관 기간 0일을 확인했다.
DB 스냅샷은 0개다. 기존 업무 테이블 58개와 Flyway 이력 1개를 TLS로 다시 조회했다.
새 SSM 검증 연결은 `96f02f36-1bad-40b0-beea-68c778bea921`이다.
