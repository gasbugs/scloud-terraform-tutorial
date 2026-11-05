# SAT · SageMaker AI · Bedrock 실무 비교

**비교 대상:** SCP Simple AI Training의 **Training Job**, Amazon SageMaker AI의 **Training Job**, Amazon Bedrock의 **Model customization/Fine-tuning job**. 앞의 두 서비스는 사용자 학습 코드를 실행하는 관리형 Job에 가깝다. Bedrock은 지원되는 기반 모델을 정해진 방식으로 조정하는 서비스다.

| 의사결정 항목 | SCP SAT Training Job | SageMaker AI Training Job | Bedrock 파인튜닝 |
|---|---|---|---|
| 주된 목적 | SCP GPU에서 사용자 데이터·코드·이미지로 학습 | AWS 관리형 컴퓨트에서 사용자 알고리즘·컨테이너로 학습 | Bedrock 지원 기반 모델을 지정된 방식으로 조정 |
| 코드·모델 제어 | 사용자 학습 스크립트 실행 지원. BYOC도 공식 소개되지만 해당 페이지에는 2026년 9월 제공 예정으로 표기되어 있어 현재 계정·리전에서의 실제 제공 상태 확인 필요 | 알고리즘/이미지·하이퍼파라미터·인스턴스·입출력 설정 가능 | 지원 모델·리전·학습 데이터 형식·하이퍼파라미터에 종속. 임의 `train.py` 실행을 전제로 설계하지 않음 |
| 데이터와 산출물 | SCP Object Storage 등 지원 스토리지에서 입력·출력을 관리. 실행 시 File Storage 연결과 결과 저장 경로는 Job 설정·계정 기능으로 확인 | S3/EFS/FSx 입력, S3 출력. 모델 파일을 다른 환경에서 재사용 가능 | S3에 학습 데이터와 지표. 맞춤 모델 자체는 Bedrock 관리 저장소에 보관 |
| 관찰·문제 해결 | SAT Job 상세, 모니터링, 로그, 결과 위치. 실제 사용 가능한 지표는 계정·Job 증거로 확인 | Training Job 상태, CloudWatch 로그·지표, S3 산출물 | Job의 validation/processing/training 단계 상태와 학습·검증 지표 확인. 컨테이너 내부 디버깅 자유도는 제한적 |
| Spot·중단 대응 | 공식 소개에는 Spot 중단·재개 관리, GPU/하드웨어 장애 Job Failover, 체크포인트 저장이 각각 명시됨. 저장된 Spot 생성 화면에는 `Job Failover` 사용 불가 표시. 두 기능의 동시 적용 조건은 실제 서비스 설정 확인 필요 | Managed Spot의 중단·재시작과 S3 체크포인트 복원 지원. 코드가 체크포인트 저장·복원을 구현해야 이어서 학습 가능. Spot 용량이 없다고 On-Demand로 자동 전환하지 않으며 최대 대기 시간 초과 시 중지 | 사용자가 Spot 인스턴스·GPU 장애 복구 방식을 Job 옵션으로 직접 정하는 형태가 아님 |
| 운영 책임 | SCP GPU 할당량, 스토리지·레지스트리 연동, 코드·데이터·체크포인트 전략 | IAM, S3/EFS/FSx, 네트워크, 컨테이너, 코드·체크포인트 전략 | 지원 모델/리전 선택, 규격에 맞춘 데이터, IAM·S3, 맞춤 모델 사용 방식 |
| 결과 이동성 | 사용자 스토리지에 저장된 모델 파일의 형식·접근 권한·반출 경로에 따라 외부 재사용 가능 여부가 결정됨. 서비스 차원의 반출 지원과 파일 접근을 구별 | S3 모델 산출물에 접근 가능. 외부 재사용은 모델 형식·런타임 의존성에 따라 결정 | 맞춤 모델을 Bedrock 관리 저장소에서 사용하는 구조. 일반 가중치 파일 반출을 가정하지 않음 |
| 비용 판단 | Spot·On-Demand·약정과 GPU·스토리지·대기/재시도 조건을 견적에 반영 | 인스턴스·Managed Spot·스토리지·로그·대기/재시도 등을 전체 실행 기준으로 계산 | 모델별 학습·맞춤 모델 사용/추론 조건을 별도 견적으로 확인 |

## 실무 선택 예시

- **기존 PyTorch/LoRA 코드, 임의 입력 전처리, 자체 모델 파일이 핵심:** SAT 또는 SageMaker가 직접 비교 대상이다. SCP 사용 조직이면 SAT의 GPU·스토리지 할당량과 실제 지원 이미지·명령을 먼저 확인한다.
- **AWS 안에서 컨테이너 Job을 자동화하고 S3/CloudWatch·IAM을 이미 운영:** SageMaker가 운영 도구와 연동하기 쉽다.
- **지원 기반 모델을 정해진 형식으로 파인튜닝하고 Bedrock에서 활용:** Bedrock이 간결하다. 우리 `demo-main.zip`의 원본 `train.py`나 LLM03 원본 LoRA 코드를 그대로 실행하는 요구와는 다르다.
- **원가 결론:** 공개 소개만으로 우열을 단정하지 않는다. 같은 모델·데이터·성공 기준으로 총 실행 시간, 대기·중단, 스토리지, 추론·모델 사용료를 계산한다.

## 확인한 근거와 한계

- [SDS Simple AI Training 제품 소개](https://www.samsungsds.com/kr/aiml-simple-ai-training/simple-ai-training.html): 관리형 학습, 코드/데이터, 스토리지, Spot, GPU Failover, 체크포인트에 관한 공개 설명. 공개 페이지의 `BYOC 2026년 9월 예정` 문구는 **2026년 11월 현재 제공 여부의 증거가 아니다**. 저장된 생성 화면의 이미지·Command 필드와 실제 계정 사용 가능 범위를 구분한다.
- [삼성SDS GPU Failover 기술 설명](https://www.samsungsds.com/kr/insights/multi-cluster-gpu-failover.html): 하드웨어 장애 시 재배치, 코드·설정 오류는 대상 아님, 체크포인트 전략의 필요성. 이는 Spot 자원 회수 후 재개와 다른 장애 유형이다.
- [SageMaker CreateTrainingJob API](https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateTrainingJob.html): 컨테이너/알고리즘, 입력, 출력, 리소스, Managed Spot, IAM. [Managed Spot](https://docs.aws.amazon.com/sagemaker/latest/dg/model-managed-spot-training.html) 및 [체크포인트](https://docs.aws.amazon.com/sagemaker/latest/dg/model-checkpoints.html): 중단·재시작 조건과 사용자 코드의 저장·복원 책임. [출력 처리](https://docs.aws.amazon.com/sagemaker/latest/dg/your-algorithms-training-algo-output.html): S3 모델 산출물.
- [Bedrock 지원 파인튜닝 모델](https://docs.aws.amazon.com/bedrock/latest/userguide/custom-model-fine-tuning.html), [Job 제출](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-submit.html), [결과 분석](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-analyze.html): 지원 범위, S3 지표, 맞춤 모델 보관 방식.
- 보유 자료 `scp_sat_videos/SCP Simple AI Training 상품설명회 영상_261027_audio_only.txt` 02:02–03:20·06:17–10:07, `[KR] AI워크로드를 위한 SCP GPUaaS 아키텍처 설계_2610_audio_only.txt` 12:07–17:35. 전사 발화와 제품의 현재 계약 조건은 구분한다.
- 사용자가 저장한 Spot 생성 화면과 로컬 `/reference/job-spot.html`의 `Job Failover` 사용 불가 표시와 `/local`의 저장된 실행 기록은 **실제 SCP 계정에서 모든 기능을 검증한 결과가 아니다**. AWS G6 Docker 결과도 SageMaker 실행 검증이 아니다.
