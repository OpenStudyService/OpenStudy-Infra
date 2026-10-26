# 빈 DB의 V1~V3 초기 적용 준비

작업일: 2026-10-26 (Asia/Seoul).
관련 이슈: [Infra #1](https://github.com/OpenStudyService/OpenStudy-Infra/issues/1).

## 문제와 작업 범위

Infra는 V1 SQL만 배포하고 있었다. 최신 Backend는 V2·V3에서 추가한 테이블과 항목도 사용한다.
사용자는 AWS RDS의 실제 테이블 목록이 비어 있다고 확인했다.
이번 작업은 빈 DB에 V1~V3을 처음 적용하는 경로를 준비한다.
과거 문서의 V1 적용 기록을 현재 RDS 상태로 단정하지 않는다.
에이전트는 실제 RDS를 조회하거나 변경하지 않았다.

## 결정과 구현

기존 Infra의 S3·SSM·Flyway 실행 경로를 재사용한다.
DB 변경 실행은 Infra가 담당한다. Backend는 Flyway를 끄고 테이블 구조를 검사한 뒤 기동한다.
기존 실행 경로에서 SQL 세 파일을 처리할 수 있어 배포 방식을 새로 만들 필요가 없었다.

- 기존 `V1__initial_schema.sql`은 수정하지 않는다.
- Backend 커밋 `3484d1c6abd31f79377779b606d9b43767660544`에서 V2·V3을 원문 그대로 가져온다.
- Terraform은 SQL 세 파일과 실행 스크립트를 S3에 게시하고 SSM 작업에 전달한다.
- Infra의 마이그레이션이 켜진 동안 Service의 `SPRING_FLYWAY_ENABLED=true` 또는 같은 이름의 시크릿 주입을 거부한다.
- 일회용 DB 검사에 V1~V3 성공 이력, 테이블 수, Flyway validate와 선택적인 Backend JAR 기동 검증을 추가한다.

원본과 실행 담당은 [SQL 안내](../../database/migrations/README.md)에 기록했다.
V3만 실행하지 않는다. 세 파일을 순서대로 적용한 결과가 V3 상태다.
기존 RDS를 계속 사용하며 버전마다 새 RDS를 만들지 않는다.

## 실제 검증 결과

### 일회용 MySQL과 Backend

로컬 Docker의 내부 전용 네트워크와 임시 메모리 DB를 사용했다.
외부 포트를 열지 않았다. 테스트용 자체 인증서와 임시 DB의 root 계정만 사용했다.
운영용 DB 계정과 비밀값은 사용하지 않았다.

- MySQL 8.4.11, Flyway 11.20.2, MariaDB JDBC 3.5.9, Java 21을 사용했다.
- 위 Backend 원본을 임시 경로에 받아 Java 21과 Gradle Wrapper 9.8.1로 `bootJar` 빌드에 성공했다. Backend 소스는 수정하지 않았다.
- Infra의 V1~V3을 빈 DB에 순서대로 적용했다. 성공 이력은 `1/true`, `2/true`, `3/true`였다.
- 업무·세션 테이블 65개와 Flyway 이력 테이블 1개를 확인했다.
- `flyway validate`가 성공했다. 같은 SQL의 두 번째 적용은 추가 0건이었다.
- Backend의 Flyway를 끄고 Hibernate `ddl-auto=validate`로 해당 DB에 연결했다. 테이블 구조 검사와 서버 기동이 성공했다.
- Flyway와 Backend의 DB 연결에서 TLS 인증서를 확인했다. 잘못된 호스트 이름과 신뢰하지 않는 CA 연결은 거부됐다.
- 검증용 사본의 V1을 변경했을 때 Flyway가 checksum 불일치로 중단했다. 원본 V1은 수정하지 않았다.
- 종료 후 검증용 컨테이너와 네트워크를 삭제했다. 내려받은 Docker 이미지는 남는다.

실행 명령은 다음과 같다. 이 환경에서는 Python의 CA 파일을 명시했다.

```sh
SSL_CERT_FILE=/opt/homebrew/etc/openssl@3/cert.pem \
  python3 scripts/check-database.py --backend-jar /absolute/path/to/backend.jar
```

### 저장소 전체 검사

Terraform 1.16.6으로 `./scripts/validate.sh`를 실행해 종료 코드 0을 확인했다.

- Terraform fmt·3개 스택 init/validate 및 모의 테스트 47개 통과(AWS 34개, Cloudflare 5개, Frontend 8개).
- Bootstrap 구문·크기 검사 6개 구성 통과.
- Node 검사 12개 통과.
- Python 48개 중 43개 통과. Nginx 실행 파일을 지정하지 않아 CORS 검사 5개는 건너뛰었다.
- 새 Terraform 테스트의 첫 실행은 필요한 Frontend 모의 설정이 빠져 실패했다. 설정을 보완한 뒤 위 전체 검사를 통과했다.

## 남은 작업

이 PR은 빈 DB 초기 적용과 실행 담당 단일화의 준비 작업이다.
로컬 검증을 실제 RDS나 운영 앱의 검증 결과로 취급하지 않는다.

- 사용자가 PR을 검토·병합한 뒤 실제 적용 계획을 확인한다.
- 실제 대상 DB가 비어 있는 경우 V1~V3을 적용하고 성공 이력을 기록한다.
- 기존 데이터가 발견되면 적용을 멈추고 별도 업그레이드·백업·복구 절차를 따른다.
- 운영 앱의 최소 권한 계정·비밀값 주입·별도 OWNER 초기화·로그인·세션 재기동은 후속으로 검증한다.
- 기존 V1 데이터 복제본의 업그레이드와 실제 백업·복구는 이번 검증 범위에 포함하지 않았다.

실제 RDS 적용, 리소스 생성·삭제, PR 병합, 자동 백업 변경은 수행하지 않았다.
Infra #1은 실제 DB 확인과 후속 인수 조건이 남아 열린 상태를 유지한다.
