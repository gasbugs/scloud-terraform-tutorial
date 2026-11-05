# 영상용 화면 원고 · SAT와 AI 학습 운영 6편

[녹화 구성안](TEACHING_GUIDE.md)의 4개 장면에 대응한다. 20분 영상은 아직 녹화·실측하지 않았다. 이론은 AI 학습 전체를 다루고, 화면 실습은 Training Job만 사용한다. 로컬 화면은 교육용 구현이며 보존 결과는 AWS G6 실행 기록이다.

## 1편 · 학습 흐름과 재현성

데이터 정제 → train/validation/test → 학습 → 검증 → 모델 저장 → 추론 활용. SAT Job은 이 흐름의 학습 실행 구간에 있다.

| 같은 Job명으로 변경한 항목 | 달라질 수 있는 것 |
|---|---|
| 데이터 revision | 학습 예시·분할 |
| 모델 revision | 시작 가중치 |
| seed·평가 표본 | 실행·비교 조건 |

원본 demo input-manifest.json: train 2,700·validation 540·test 540, seed 42. run-config.json: max_steps 10, eval_samples 20. 변경 후 점수는 실제 재실행한 자료가 없으므로 제시하지 않는다.

## 2편 · Training Job 입력·출력과 생성 설정

[원본 demo 상세](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details): 원본 스토리지 → 컨테이너 /work → 이미지·Command → 결과 위치. 입력 기반 모델 model/model.safetensors와 출력 adapter/adapter_model.safetensors를 구별한다.

[저장된 Training Job 생성 화면](http://127.0.0.1:8080/reference/job-new.html): 학습 형태·이름 → GPU·노드 → 이미지·권한 → Command → Volume/Object Storage → 요약. On-Demand는 Training Job의 실행 방식 예시다. 제출·실행은 하지 않는다.

## 3편 · Spot Training Job과 복구

| 사건 | 확인할 것 |
|---|---|
| Spot 자원 회수 | 대기·중단·재개 |
| GPU 하드웨어 장애 | Job Failover 적용 조건 |
| 코드·설정 오류 | 코드·경로·이미지 수정 |
| 학습 상태 손실 | 체크포인트 저장·복원 |

[저장된 Spot 화면](http://127.0.0.1:8080/reference/job-spot.html)의 Failover 사용 불가 표시를 보여 준다. 가상 60분 학습에서 10분 저장 간격은 다음 저장 직전 최대 약 10분, 30분 간격은 최대 약 30분의 계산을 다시 할 수 있다. 이는 실제 중단 측정값이 아니다. 원본 demo checkpoint-10은 저장 증거이며 Spot 복원 성공 증거가 아니다.

## 4편 · 상태와 실제 로그

[원본 demo](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details): 입력 다운로드 → 학습 가능 파라미터 약 0.0319% → 10 step → 어댑터·체크포인트 업로드.

[한국어 텍스트 Job](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/details): 신규 분류 헤드 초기화 경고 → epoch 1·2 학습 로그. 경고는 실패와 다르다. 가져온 로그의 시각 필드는 비어 있고 GPU 시계열은 보존되지 않았다. Completed는 성능 향상 판정이 아니다.

## 5편 · 평가와 추론 인계

| Job | 평가 표본 | 학습 전→후 | 판정 |
|---|---:|---:|---|
| 한국어 텍스트 | 700 | 정확도 16.0%→85.29% | 이 test셋에서 개선 |
| 이미지 | 2,000 | 정확도 11.2%→86.2% | 이 test셋에서 개선 |
| 원본 demo | 20 | intent accuracy 5%→5% | 이 평가에서 개선 확인 안 됨 |

이미지 혼동행렬은 코트·셔츠의 오분류를 보여 준다. 모델 파일만으로 추론 준비가 끝나지 않는다.

| 과제 | 함께 인계할 것 |
|---|---|
| 텍스트 | 가중치, tokenizer, 라벨 설정, 제목 토큰화(max_length 64) |
| 이미지 | model.pt, CNN 코드, 28×28 회색조·픽셀 /255 |
| 원본 demo | 기반 모델 revision, LoRA 어댑터, tokenizer, 채팅 템플릿 |

저장 모델 재로딩 기록은 있다. 별도 추론 서비스 배포·요청 출력 검증은 없다.

## 6편 · SAT·SageMaker·Bedrock 선택

| 요구 | 후보 | 확인 조건 |
|---|---|---|
| 기존 학습 코드·이미지 | SAT, SageMaker | BYOC·GPU 할당량·스토리지·IAM |
| 지원 기반 모델 조정 | Bedrock | 모델·리전·데이터 형식 |
| 중단 가능한 긴 학습 | SAT Spot, SageMaker Managed Spot | 체크포인트·대기 한도·Failover 범위 |

[공식 근거 비교표](SERVICE_COMPARISON.md)의 미확인 조건을 남긴다. 같은 작업과 성공 기준의 총비용 견적 없이 가격 우열을 단정하지 않는다.
