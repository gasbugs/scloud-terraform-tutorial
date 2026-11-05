# 발표용 교안 · SAT Training Job 8차수

이 Markdown은 차수별 화면 원고다. 각 화면의 **굵은 질문**을 먼저 던지고, [강사용 스크립트](TEACHING_GUIDE.md)의 5분 블록에 맞춰 실제 로컬 페이지로 전환한다. 제품의 현재 지원 상태와 교육용 로컬 구현을 구분한다. 비교 근거는 [SERVICE_COMPARISON.md](SERVICE_COMPARISON.md)에 있다.

---

## 1차수 · 왜 SAT Training Job인가

### [1-1] GPU VM 운영 대신 Job 제출

`입력 데이터 + 학습 코드/이미지 + 실행 명령 → GPU Job → 모델·지표·로그`

- 사용자: 데이터·코드·경로의 정확성 책임
- SAT: 학습 자원 구성과 Job 실행 흐름 관리
- **질문:** 입력 경로가 틀리면 GPU가 문제를 해결할까?

### [1-2] AWS와의 정확한 대응 관계

| SAT Training Job | SageMaker AI Training Job | Bedrock 파인튜닝 |
|---|---|---|
| 사용자 코드·컨테이너 Job | 사용자 코드·컨테이너 Job | 지원 기반 모델의 관리형 조정 |

- 자체 `train.py` 재사용 후보: SAT·SageMaker
- 지원 모델을 규격 데이터로 조정: Bedrock
- **질문:** 기존 코드 그대로 실행해야 한다면 Bedrock을 첫 후보로 둘 수 있을까?

### [1-3] 선택은 리전·할당량·견적까지

- SCP: SAT 계정의 GPU·스토리지·BYOC 실제 상태 확인
- AWS: SageMaker IAM·S3·네트워크 설정 확인
- Bedrock: 지원 모델·리전·데이터 형식 확인
- 공개 소개만으로 비용 우열 결론 금지

**출처:** `scp_sat_videos` 상품설명회 00:09–03:20, [SDS SAT](https://www.samsungsds.com/kr/aiml-simple-ai-training/simple-ai-training.html), [SageMaker API](https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateTrainingJob.html), [Bedrock 지원 모델](https://docs.aws.amazon.com/bedrock/latest/userguide/custom-model-fine-tuning.html).

---

## 2차수 · Job의 입력·출력 경로

### [2-1] 같은 데이터의 서로 다른 두 위치

`사용자 스토리지의 원본 → Job에 연결된 스토리지 → 컨테이너 내부 Mount Path`

- 이미지 URL: 실행 환경과 코드
- Command: 컨테이너 안에서 실행할 명령
- 결과 파일: 모델·지표·로그
- **질문:** Object Storage URI와 `/bundle`은 같은 문자열이어야 할까?

### [2-2] 원본 demo에서 찾기

[입력 준비](http://127.0.0.1:8080/local#assets) → [원본 demo 상세](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details) → 로그 → 결과 파일

**학습자 표:** `필드 / 실제 값 / 컨테이너 내부 또는 외부 / 근거 링크`.

---

## 3차수 · On-Demand Job 생성

### [3-1] 화면의 설정 순서

1. 학습 형태·Job명
2. Framework·Failover·GPU·노드
3. AI Training Image·레지스트리 접근
4. Command·Volume/Object Storage·요약

- **질문:** 이미지 안에 `train.py`가 없는데 Command가 그 파일을 호출하면?

### [3-2] 제출 전 일곱 항목 점검

`이름 / GPU 할당량 / 이미지 접근 / 코드 존재 / 명령 / 입력 마운트 / 출력 위치`

[저장된 On-Demand 생성 화면](http://127.0.0.1:8080/reference/job-new.html)을 읽는다. 수업에서는 **생성을 누르지 않는다.** 로컬 고정 G6/L4 값은 SCP 전체 상품 선택 범위를 뜻하지 않는다.

---

## 4차수 · Spot과 GPU Failover를 구분

### [4-1] 셋은 다른 문제를 다룬다

| 상황 | 의미 | 준비·확인 |
|---|---|---|
| Spot 자원 회수 | 유휴 자원을 돌려줘야 함 | 대기·중단·재개 조건 확인 |
| GPU/하드웨어 장애 | 실행 중인 노드 고장 | Job Failover 적용 범위 확인 |
| 학습 상태 손실 | 재시작 때 진행분 소실 | 체크포인트 저장·복원 코드 |

- 코드·설정 오류는 GPU Failover로 해결되지 않는다.
- **질문:** 노드를 바꾸기만 하면 이전 학습 단계가 돌아올까?

### [4-2] 공개 기능 소개와 실제 생성 화면

- SDS 공개 소개: Spot 중단·재개, GPU 장애 Failover, 체크포인트 기능을 각각 소개
- [저장된 Spot 화면](http://127.0.0.1:8080/reference/job-spot.html): `Spot Training에서는 Job Failover 사용 불가` 표시
- 결론: **Spot Job에 두 기능을 동시에 적용할 수 있는 조건은 실제 계정·리전에서 확인**

### [4-3] AWS Managed Spot도 조건부

- SageMaker가 Spot 중단 후 재시작·S3 체크포인트 이동을 관리
- 학습 코드가 체크포인트를 저장·복원해야 이어서 학습
- Spot 용량 부족 시 On-Demand 자동 전환 없음; 최대 대기 시간에 중지 가능

**출처:** [SDS SAT](https://www.samsungsds.com/kr/aiml-simple-ai-training/simple-ai-training.html), [GPU Failover 기술 설명](https://www.samsungsds.com/kr/insights/multi-cluster-gpu-failover.html), [SageMaker Managed Spot](https://docs.aws.amazon.com/sagemaker/latest/dg/model-managed-spot-training.html).

---

## 5차수 · 실행 상태와 증거

### [5-1] `Completed`가 대답하지 않는 것

- 설정: 무엇을 요청했나?
- 상태: 끝났나, 대기 중인가, 실패했나?
- 로그: 무슨 일이 일어났나?
- 평가: 얼마만큼 맞혔나?
- 결과 파일: 무엇이 저장됐나?

**질문:** `Completed` 하나로 모델 품질을 말할 수 있을까?

### [5-2] 문제를 원인별로 분류

`입력 누락 / 이미지 접근 실패 / Command 경로 오류 / GPU 할당 문제 / Spot 중단 / GPU 장애`

- 코드·설정 오류: 입력·이미지·명령 수정
- Spot 중단: 대기·재시작·체크포인트 확인
- GPU 장애: 적용 가능한 Failover와 로그 확인

### [5-3] 평가값의 출처 표시

- 한국어 텍스트 test 700건: 정확도 16.0% → 85.29%
- 이미지 test 2,000건: 11.2% → 86.2%
- **AWS G6 Docker에서 측정, 로컬 UI로 가져온 값**
- SCP SAT나 SageMaker Job을 실제 실행해 얻은 값으로 표기하지 않음

---

## 6차수 · 상세·로그 읽기

### [6-1] 두 Job 비교

| 기록 | 확인할 필드 |
|---|---|
| [원본 demo](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details) | 이미지, Command, 리소스, 입력·출력 |
| [텍스트 Job](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/details) | 동일 필드를 비교해 차이 기록 |

**질문:** 둘 다 `Completed`면 같은 과제인가?

### [6-2] 로그 세 줄만 고르기

`시작 근거 / 학습·평가 근거 / 종료 근거`

- Job별로 실제 로그에서 찾고 시간·순서 기록
- 에러는 해당 줄의 Command·입력 설정과 연결
- 없는 GPU 시계열은 추측하지 않음

---

## 7차수 · 결과 파일과 평가

### [7-1] `Completed` 뒤에 볼 것

| 텍스트 Job | 이미지 Job |
|---|---|
| test 700건, 16.0%→85.29% | test 2,000건, 11.2%→86.2% |
| `model/model.safetensors` | `model.pt` |
| `comparison.json` | `comparison.json` |

[텍스트 비교](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/comparison) · [이미지 비교](http://127.0.0.1:8080/local#jobs/cb0e433e77965ac9ad283d14027ed2df/comparison)

### [7-2] 이동성과 반출 지원

- 파일에 접근 가능 ≠ 제품이 모든 모델의 반출을 보장
- 확인할 것: 형식, 권한, 라이선스, 추론 런타임, 결과 경로
- Bedrock 맞춤 모델은 Bedrock 관리 저장소에 보관
- **질문:** 모델 가중치 파일만 있으면 다른 환경에서 즉시 동작할까?

---

## 8차수 · 실무 선택 메모

### [8-1] 요구사항별 후보

| 요구사항 | 우선 후보 | 확인해야 할 조건 |
|---|---|---|
| 기존 학습 코드·이미지 유지 | SAT, SageMaker | GPU·리전·할당량·스토리지·BYOC |
| 지원 기반 모델 조정 | Bedrock | 지원 모델·리전·데이터 형식·사용 비용 |
| 중단 가능한 긴 학습 | SAT Spot, SageMaker Managed Spot | 체크포인트·대기·재개·Failover 적용 범위 |

### [8-2] 결론은 증거와 미확인 조건을 함께

`요구사항 → 후보 선택 → 공식 근거 → 계정에서 확인할 것 → 전체 비용·종료 조건`

- 가격 우열은 동일 모델·데이터·성공 기준의 견적으로 판단
- 이번 과정에서는 신규 GPU·EC2 자원 생성 없음
- [실무 비교표](SERVICE_COMPARISON.md)의 `확인한 근거와 한계`를 발표에 첨부
