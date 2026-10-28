# DB 초기 적용 SQL

빈 DB에는 Backend의 통합 `V1__init_schema.sql`을 적용한다.
원본은 Backend 커밋 [`f36e451`](https://github.com/OpenStudyService/OpenStudy-Backend/blob/f36e4519848564b17dd8a795a36dfbb63e83eebb/src/main/resources/db/migration/V1__init_schema.sql)이다.
파일 이름과 내용을 그대로 유지한다.

Infra의 SSM 작업이 전용 마이그레이션 계정으로 Flyway를 실행한다. Backend 운영 환경은 Flyway를 실행하지 않는다.
계정을 준비한 뒤 마이그레이션을 활성화한다. 자세한 절차는 [DB 배포 문서](../../docs/database.md#db-계정-준비)를 따른다.
처음 적용하면 업무·세션 테이블과 `flyway_schema_history` 이력이 생성된다.
같은 파일을 다시 실행하면 추가 적용이 없다.

구형 V1~V3 이력은 통합 V1과 호환되지 않는다. 기존 이력이 있으면 적용을 중단하고 별도 전환 절차를 정한다.
기존 체크섬을 자동으로 바꾸거나 `clean`, `repair`, `baseline`을 실행하지 않는다.
한 번 적용한 SQL은 수정하지 않는다. 이후 스키마 변경은 새 버전으로 추가한다.
