# DB 계정 분리 준비

## 배경과 결정

기존 Flyway Runner는 RDS 관리자 시크릿을 사용했다. Backend는 앱 계정에 DML만 부여하도록 요청했다.
AWS 비용이 발생하지 않도록 로컬 구현과 검증만 진행한다. 현재 실제 RDS는 없다.

관리자 계정은 최초 계정 생성에만 사용한다. Flyway는 `openstudy_migrator`, 앱은 `openstudy_app`을 사용한다.
두 비밀번호는 서로 다른 SSM Standard SecureString에 보관한다. 비밀번호는 Terraform state에 넣지 않는다.
계정 준비 전 자동 마이그레이션을 막기 위해 `apply_database_migrations` 기본값을 false로 바꿨다.

## 구현

- Runner의 IAM 권한과 입력을 관리자 시크릿에서 마이그레이션 비밀번호 파라미터로 변경했다.
- 계정 생성 스크립트는 별도 관리자 권한으로 실행한다. 비밀번호를 인수나 출력에 표시하지 않는다.
- 앱은 `openstudy_app`을 사용한다. DB_PASSWORD를 SecureString으로 전달한다. 관리자 계정과 일반 환경 변수 비밀번호는 거부한다.
- 앱에는 DML을, 마이그레이션 계정에는 필요한 DDL과 DML을 부여한다. 두 계정 모두 TLS가 필요하다.
- 계정 생성은 독립 사전 작업이다. 실패 중 일부 계정이 생성된 경우 상태를 확인하고 수동 복구해야 한다.

## 검증

- MySQL 8.4.11의 격리된 임시 DB에서 계정 생성 SQL과 권한을 검사했다.
- 마이그레이션 계정으로 통합 V1을 적용하고 Flyway validate와 재실행을 확인했다.
- 앱 계정의 SELECT, INSERT, UPDATE, DELETE를 확인했다. CREATE TABLE은 권한 부족으로 거부됐다.
- Backend PR #53을 앱 계정과 운영 프로필로 실행해 스키마 검사와 기동을 확인했다.
- Terraform 모의 검사 AWS 37개, Cloudflare 5개, Frontend 8개가 통과했다. Node 12개, Python 44개가 통과했다. Nginx 5개는 도구가 없어 건너뛰었다.
- 계정 생성 스크립트의 실제 AWS 시크릿 조회와 실제 RDS 접속은 검증하지 않았다.

## 남은 작업

실제 RDS 생성, SecureString 준비, 전용 계정 생성, 서버 배포는 수행하지 않았다.
실제 구축은 비용과 접속 경로를 확인한 뒤 진행한다. AWS 리소스 생성이나 DB 적용 결과로 표시하지 않는다.
