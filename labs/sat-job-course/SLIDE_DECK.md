# 영상용 화면 원고 · SAT와 AI 학습 운영 7편

[녹화 구성안](TEACHING_GUIDE.md)의 장면에 대응하는 화면 자료다. 20분 영상은 아직 녹화·실측하지 않았다. 각 화면은 새로운 개념 또는 실제 자료를 제시하며 시청자 답변을 기다리지 않는다. 로컬 시연은 교육용 구현이고 결과는 AWS G6 실행 기록이다.

## 1차수 · AI 학습 흐름과 SAT의 위치

데이터 수집·정제 → train/validation/test 분할 → 코드·이미지 준비 → SAT GPU Job → 모델·지표 저장 → 재로딩·활용

| 사용자 책임 | 관리형 Job의 역할 |
|---|---|
| 데이터 의미·품질, 분할, 코드·이미지·명령, 결과 검증 | GPU 자원 배치와 Job 실행·상태 관리 |

Completed는 실행 종료다. 모델 품질과 활용 가능성은 별도로 확인한다. 서비스 선택은 7편에서 다룬다.

## 2차수 · 재현 가능한 입력·출력

[원본 demo](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details)의 input-manifest.json에는 데이터·모델 revision, seed 42, train 2,700·validation 540·test 540건이 남았다. run-config.json의 max_steps 10과 eval_samples 20은 이번 짧은 실행 범위다.

원본 위치 → 컨테이너 /work → 실행 명령 → 결과 위치. 입력 model/model.safetensors와 출력 adapter/adapter_model.safetensors를 구별한다. AWS S3 경로를 SCP Object Storage 경로로 소개하지 않는다.

## 3차수 · On-Demand Job 설정

[저장된 생성 화면](http://127.0.0.1:8080/reference/job-new.html)의 학습 형태·Job명 → GPU·노드·Shared Memory → 이미지·레지스트리 → Command → 스토리지 → 요약 순서로 읽는다.

| 설정 오류 | 예상되는 확인 지점 |
|---|---|
| 이미지 접근 불가 | 레지스트리 권한 |
| 이미지에 코드 없음 | 이미지 내용·Command |
| 입력 경로 불일치 | 스토리지 마운트·코드 경로 |
| GPU 할당량 부족 | 리소스·계정 할당량 |

설명용 오류와 실제 보존 로그를 구분한다. Job을 제출하지 않는다.

## 4차수 · Spot과 복구 조건

| 사건 | 필요한 판단 |
|---|---|
| Spot 회수 | 대기·중단·재개 조건 |
| GPU 하드웨어 장애 | Job Failover 적용 범위 |
| 코드·설정 오류 | 코드·경로·이미지 수정 |
| 진행분 손실 | 체크포인트 저장·복원 |

[저장된 Spot 화면](http://127.0.0.1:8080/reference/job-spot.html)에는 Spot Job의 Failover 사용 불가 표시가 있다. 공식 기능 소개의 Spot 재개와 GPU 장애 Failover는 별개다. checkpoint-10 파일의 존재는 실제 Spot 복원 시험의 증거가 아니다.

## 5차수 · 상태와 실제 로그

[원본 demo](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details)와 [한국어 텍스트 Job](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/details)의 설정·로그를 나란히 보여 준다.

- 상태는 준비·대기·실행·종료의 위치를 알려 준다.
- 원본 demo: 입력 다운로드 → 학습 가능 파라미터 약 0.0319% → 10 step → 어댑터·체크포인트 업로드.
- 텍스트 Job: 분류 헤드 신규 초기화 경고 → epoch 1·2 진행. 경고는 실행 실패와 다르다.
- 가져온 로그의 시각 필드는 비어 있고 GPU 시계열은 보존되지 않았다. 기록에 없는 증거는 생성하지 않는다.

## 6차수 · 결과의 품질과 한계

| Job | 평가 표본 | 정확도 전→후 | 품질 판단 |
|---|---:|---:|---|
| 한국어 텍스트 | 700 | 16.0%→85.29% | 해당 test셋에서 개선 |
| 이미지 | 2,000 | 11.2%→86.2% | 해당 test셋에서 개선 |
| 원본 demo | 20 | intent accuracy 5%→5% | 이 평가에서 개선 확인 안 됨 |

[텍스트 비교](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/comparison) · [이미지 비교](http://127.0.0.1:8080/local#jobs/cb0e433e77965ac9ad283d14027ed2df/comparison).

이미지 confusion_matrix.json: 코트 200건 중 135건 정답, 32건 풀오버, 20건 셔츠. 셔츠 200건 중 119건 정답, 34건 티셔츠/상의, 20건 풀오버. 전체 정확도만으로는 이 오류가 드러나지 않는다. 모델 파일과 지표 파일의 역할도 구별한다.

## 7차수 · SAT·SageMaker·Bedrock 선택

| 요구 | 후보 | 확인할 조건 |
|---|---|---|
| 기존 학습 코드·이미지 유지 | SAT, SageMaker | BYOC 제공·GPU 할당량·스토리지·IAM |
| 지원 기반 모델 조정 | Bedrock | 모델·리전·데이터 형식·사용 비용 |
| 중단 가능한 긴 학습 | SAT Spot, SageMaker Managed Spot | 체크포인트 코드·대기 한도·Failover 범위 |

[공식 근거 비교표](SERVICE_COMPARISON.md)의 미확인 조건을 남긴다. 같은 작업과 성공 기준의 총비용 견적 없이 가격 우열을 단정하지 않는다.
