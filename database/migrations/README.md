# DB 초기 적용 SQL

빈 DB에는 다음 세 파일을 Flyway로 순서대로 적용한다.

| 파일 | 역할 |
| --- | --- |
| `V1__initial_schema.sql` | 기본 테이블을 만든다. 기존 Infra 파일을 유지한다. |
| `V2__foundation_expand.sql` | 상품 분류·판매 지점·변경 이력, 초대 권한, 알림 기록 등을 추가한다. |
| `V3__foundation_validate_and_finalize.sql` | 데이터를 검사하고 필수값·중복 방지 규칙과 기본 권한을 적용한다. |

V2·V3의 원본은 Backend 커밋 `3484d1c6abd31f79377779b606d9b43767660544`의 [마이그레이션 폴더](https://github.com/OpenStudyService/OpenStudy-Backend/tree/3484d1c6abd31f79377779b606d9b43767660544/src/main/resources/db/migration)이다.
두 파일은 원문 그대로 배포 사본으로 가져왔다.
Infra V1은 Backend V1과 끝 줄바꿈 하나만 다르다. 파일 이름은 기존 Infra 이름을 유지한다.
이미 적용한 파일을 덮어쓰지 않는다. 이후 변경은 새 버전 파일로 추가한다.

## 실행 담당

이 구성에서는 Infra의 SSM 작업이 Flyway를 실행한다.
Backend는 `SPRING_FLYWAY_ENABLED=false`로 실행한다.
`apply_database_migrations=true`인 동안 Service의 Flyway를 켜거나 해당 설정을 시크릿으로 덮어쓰면 Terraform 검사가 실패한다.

`flyway_schema_history`는 SQL 파일이 아니라 Flyway가 실제 DB에 생성하는 적용 이력 테이블이다.
빈 DB에 적용하면 V1·V2·V3 성공 이력이 생긴다. 같은 파일로 다시 실행하면 추가 적용은 0건이다.
RDS를 버전마다 새로 만들지 않는다. V3 파일만 단독으로 실행하지 않는다.

## 기존 데이터가 있는 경우

이번 변경의 검증 대상은 빈 DB이다.
기존 상품·초대가 있으면 V3 전에 운영 근거에 따른 검토와 매핑이 필요하다.
그 경우 바로 적용하지 않고 Backend의 [기존 DB 업그레이드 절차](https://github.com/OpenStudyService/OpenStudy-Backend/blob/3484d1c6abd31f79377779b606d9b43767660544/docs/db/foundation-upgrade.md)를 따른다.
