# AI 모델 배포 준비

현재 GitOps 저장소의 ECS 배포에 임베딩 모델과 Qwen 설정을 연결합니다.
대상은 기존 `openstudy.duckdns.org` 환경과 `linux/amd64` 예산 프로필입니다.
이 문서의 준비 작업은 운영 배포 완료를 뜻하지 않습니다.

## 모델과 키의 전달 방식

- `models.zip`은 기존 비공개 Frontend 배포 버킷의 `models/` 경로에 저장합니다.
- EC2는 지정한 S3 객체 하나만 읽을 수 있습니다.
- SSM은 압축 파일의 SHA-256과 내부 파일 3개의 SHA-256을 검사합니다.
- 모든 검사가 끝난 디렉터리만 공개합니다. 중간에 실패하면 불완전한 디렉터리를 마운트하지 않습니다.
- ECS Service는 `/opt/openstudy/models/<ZIP SHA-256>/koen-e5-tiny-q8`을 읽기 전용으로 마운트합니다.
- ECS 서비스 갱신은 모델 설치 SSM 작업의 성공을 기다립니다.
- `QWEN_API_KEY`는 기존 `service_secret_parameters`로 SSM SecureString ARN만 전달합니다.
- 모델과 실제 키는 Git, 앱 이미지, Terraform 변수에 넣지 않습니다. `.env.qwen.local`은 로컬 개발용이므로 운영 컨테이너에 넣지 않습니다.

기존 Backend의 [배포 계약 11절](https://github.com/OpenStudyService/OpenStudy-Backend/blob/c3a45a9/docs/deployment/README.md#11-임베딩-모델)을 따릅니다.
모델의 원본은 `exp-models/dragonkue-KoEn-E5-Tiny-ONNX`입니다.
원본 리비전은 `5cf599a8cd6577f2f12a026130ad50132e472cfd`입니다.
전달받은 파일은 x86_64용 변환본입니다. ARM 호스트에서는 사용하지 않습니다.
원본의 Apache-2.0 라이선스와 출처를 함께 보관해야 합니다.
첨부 ZIP에는 라이선스 파일이 없으므로 배포 인계 시 별도로 확보합니다.

## 로컬 준비

GitOps 저장소 루트에서 실행합니다. Python 3.9 이상이 필요합니다.

```sh
mkdir -p artifacts/ai-model
cp /Users/pista/Downloads/models.zip artifacts/ai-model/models.zip
python3 scripts/install-ai-model.py \
  --archive artifacts/ai-model/models.zip \
  --destination artifacts/ai-model/koen-e5-tiny-q8
```

`artifacts/ai-model/`은 Git에서 제외합니다.
설치기는 이미 존재하는 정상 디렉터리를 재사용합니다.
파일이 들어 있는 불완전한 기존 디렉터리는 덮어쓰지 않고 오류를 반환합니다.
Docker가 먼저 만든 빈 디렉터리는 검사가 끝난 디렉터리로 한 번에 교체합니다.

이번 첨부 파일의 검사값은 다음과 같습니다.

| 파일 | SHA-256 |
| --- | --- |
| ZIP | `9341c713d56ac0bd646ab5b12141637b7e57b6bd80fa5a96f0d52e01064d386a` |
| manifest.json | `c1ef84e7200635659580ea2e057f0b6c4d2fe9f56b5bc80f4b4ccf3385450f98` |
| model_quint8_x86_64.onnx | `ef00d6227284038a3338a92273ca0e89971f93f966ab5eabfd6a8fc0bea9459e` |
| tokenizer.json | `a6dd38d692ac1caa6d5dbc195d92f1f978b5c74ec60e02ed15fdf04404742fe3` |

설치기의 고정 검사값을 바꾸지 않고 다른 모델을 넣을 수 없습니다.
모델 교체는 Backend의 모델 명세와 함께 검토해야 합니다.

## 배포 설정 준비

`terraform/aws/profiles/ai.tfvars.example`을 로컬 `ai.tfvars`로 복사합니다.
대상 계정과 접두어를 기존 환경에 맞춥니다.
`service_secret_parameters` 맵에는 기존 DB·메일 비밀값 참조도 모두 유지합니다.
Terraform은 여러 tfvars 파일의 맵을 자동으로 합치지 않습니다.

실제 Qwen 키는 대상 계정의 `/<name_prefix>/apps/qwen-api-key`에 SecureString으로 등록합니다.
기존 ECS 실행 역할은 기본 SSM KMS 키를 사용하는 이 경로의 매개변수만 읽습니다.
키를 CLI 인자, tfvars 또는 Git에 적지 않습니다.

`enable_ai_live=true`는 다음 값을 주입합니다.

| 환경 변수 | 값 |
| --- | --- |
| OPENSTUDY_AI_MODEL_MODE | live |
| DOMAINLENS_MODEL_MODE | live |
| DOMAINLENS_EMBEDDING_PROVIDER | onnx |
| DOMAINLENS_EMBEDDING_DIRECTORY | 검증된 모델의 절대 경로 |
| QWEN_BASE_URL | https://token-plan.maas.qwencloudapi.com/compatible-mode/v1 |
| QWEN_MODEL | qwen3.8-flash |

현재 Backend는 thinking을 코드 설정으로 끕니다.
모델 파일만 준비하려면 `ai_model_archive_path`만 지정하고 `enable_ai_live=false`를 유지합니다.
기본값은 모델 배포 없음과 live 호출 비활성입니다.

## 계획과 적용

배포 준비 단계의 검증은 AWS 모의 공급자를 사용합니다.
AWS 리소스를 생성하거나 실제 Qwen을 호출하지 않습니다.

```sh
python3 -m unittest discover -s tests -p 'test_install_ai_model.py' -v
terraform -chdir=terraform/aws init -backend=false -input=false
terraform -chdir=terraform/aws validate
terraform -chdir=terraform/aws test -filter=tests/ai.tftest.hcl
```

운영 적용 전에는 기존 변수 파일과 예산 프로필을 모두 사용해 계획을 검토합니다.
아래 예시는 실제 배포 단계의 명령입니다.

```sh
terraform -chdir=terraform/aws plan \
  -var-file=profiles/budget.tfvars.example \
  -var-file=ai.tfvars \
  -out=ai.tfplan
terraform -chdir=terraform/aws apply ai.tfplan
```

적용 순서는 로컬 ZIP 검사 → 비공개 S3 업로드 → 호스트 검사·설치 → ECS 갱신입니다.
S3 업로드 전에 설치기가 ZIP 내용도 검사합니다.
`plan`만으로는 ZIP 내용 검사가 실행되지 않으므로 로컬 준비 명령을 먼저 실행합니다.

## 실제 배포 전에 필요한 항목

- 실제 Backend 이미지의 ECR digest가 필요합니다.
- 현재 ECS 코드는 Gateway와 Service 이미지를 모두 요구합니다. Backend는 단일 앱이므로 Gateway 구성을 확정해야 합니다.
- 이미지와 일치하는 DB 마이그레이션을 적용해야 합니다. 현재 Infra의 V1만으로 최신 Backend를 실행할 수 없습니다.
- `DB_URL`, 앱 전용 DB 계정, `DB_PASSWORD`, `TRUSTED_PROXIES`가 필요합니다.
- Qwen SecureString의 실제 값과 사용 가능한 키를 확인해야 합니다.
- 모델의 라이선스 문구를 배포 인계 자료에 포함해야 합니다.

이 준비 변경은 위 항목을 대신 구현하거나 운영에 적용하지 않습니다.
현재 저장소에는 전체 Backend 자동 CI/CD가 연결되어 있지 않습니다.
이 파일을 추가하는 것만으로 자동 배포가 시작되지는 않습니다.

## 배포 후 확인과 복구

1. SSM 모델 설치 결과가 `Success`인지 확인합니다.
2. ECS Service의 모델 마운트가 읽기 전용인지 확인합니다.
3. Backend 로그에서 `Local embedding ready`, `linux-x86_64`, `dimensions=384`를 확인합니다.
4. 로그인 후 `/api/ai/catalog/readiness`의 `warnings`가 비었는지 확인합니다. `ready: true`만으로 모델 설치를 판정하지 않습니다.
5. 실제 AI 질문 1건의 결과와 Qwen 호출 기록을 확인합니다. 이 단계는 토큰을 사용합니다.

키만 교체해도 실행 중인 컨테이너의 환경 변수는 바뀌지 않습니다.
새 태스크 배포 후 연결 상태를 확인합니다. [AWS의 SSM 비밀값 주입 안내](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-ssm-paramstore.html)를 따릅니다.
장애 시 이전 앱 digest와 모델 경로를 사용한 태스크 정의로 돌아갑니다.
이전 태스크가 쓰는 모델 디렉터리는 지우지 않습니다.
모델을 해제하려면 `ai_model_archive_path=null`, `enable_ai_live=false`로 계획을 확인합니다.
배포용 S3 버킷과 EC2의 모델은 기존 전체 환경 삭제 범위에 포함됩니다.
