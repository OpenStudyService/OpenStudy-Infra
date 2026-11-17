# DB 초기 적용 SQL

빈 DB에는 Backend의 V1~V22와 Infra의 V23을 순서대로 적용한다.
V1의 최초 원본은 Backend 커밋 [`f36e451`](https://github.com/OpenStudyService/OpenStudy-Backend/blob/f36e4519848564b17dd8a795a36dfbb63e83eebb/src/main/resources/db/migration/V1__init_schema.sql)이다.
2026-11-17에 [`c3a45a9`](https://github.com/OpenStudyService/OpenStudy-Backend/tree/c3a45a933cd4b3210b0604a03238bfbd1c80e285/src/main/resources/db/migration)의 V2~V22를 추가했다.
22개 파일 모두 해당 커밋과 바이트 단위로 같다. 기존 V1은 변경하지 않았다.

V23은 2026-11-17 사용자가 승인한 다중 OWNER 정책을 적용한다.
`employees.owner_slot`의 단일 OWNER 고유 인덱스만 제거한다. 기존 계정과 이메일 고유 제약은 유지한다.
Backend의 활성 OWNER 수 검사와 마지막 관리자 보호는 그대로 사용한다.
V23은 Infra에서 관리하는 후속 버전이다. Backend SQL을 동기화할 때 같은 버전 번호를 덮어쓰지 않는다.
OWNER 추가 절차는 [운영 문서](../../docs/add-owner.md)에 기록한다.

Infra의 SSM 작업이 전용 마이그레이션 계정으로 Flyway를 실행한다. Backend 운영 환경은 Flyway를 실행하지 않는다.
계정을 준비한 뒤 마이그레이션을 활성화한다. 자세한 절차는 [DB 배포 문서](../../docs/database.md#db-계정-준비)를 따른다.
처음 적용하면 업무·세션 테이블과 `flyway_schema_history` 이력이 생성된다.
최종 구성은 업무·세션 테이블 80개, 이력 테이블 1개, `seat_occupancy_samples` 뷰 1개다.
같은 파일을 다시 실행하면 추가 적용이 없다.

구형 V1~V3 이력은 통합 V1과 호환되지 않는다. 기존 이력이 있으면 적용을 중단하고 별도 전환 절차를 정한다.
기존 체크섬을 자동으로 바꾸거나 `clean`, `repair`, `baseline`을 실행하지 않는다.
한 번 적용한 SQL은 수정하지 않는다. 이후 스키마 변경은 새 버전으로 추가한다.

V8은 기존 AI 결과 데이터 열을 제거한다. V18은 폐기된 `ai_export_approvals` 테이블을 제거한다.
기존 DB를 업그레이드할 때는 백업과 적용할 변경을 먼저 확인한다.
V20~V21을 적용할 마이그레이션 계정에는 `CREATE VIEW`, `SHOW VIEW` 권한이 필요하다.
로컬 덤프 검증은 [별도 절차](../../docs/database-dump.md)를 따른다. 데이터 덤프를 이 디렉터리에 넣지 않는다.
