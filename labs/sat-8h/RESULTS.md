# G6 검증 결과 — 2026-11-05

## 환경과 범위

- AWS us-east-1의 임시 `g6.xlarge`, NVIDIA L4 23,034 MiB, Docker GPU 런타임.
- CPU 준비 후 `.state/sat-8h/bundle`을 G6에 전송했다. 컨테이너에서 번들 해시·클래스 균형·CPU 모델 전방 계산을 다시 통과했다.
- 이 결과는 **AWS EC2 Docker에서 검증**했다. Samsung Cloud Platform SAT에서 Job을 실제 제출한 결과가 아니다.
- 전체 로그와 출력은 무시된 `.state/sat-8h/g6-results`에 보존한다. 코드와 샘플만 저장소에 둔다.

## 신규 학습 결과

| 과제 | 학습/검증/test | 학습 전 test 정확도 | 학습 후 test 정확도 | 학습 후 macro-F1 | 모델 재로딩 |
|---|---:|---:|---:|---:|---|
| 한국어 YNAT, KLUE BERT | 2,100/420/700 | 16.0% | 85.29% | 0.8514 | 통과 |
| Fashion-MNIST, CNN | 12,000/1,500/2,000 | 11.2% | 86.2% | 0.8600 | 통과 |

텍스트 모델은 validation macro-F1이 가장 높았던 1 epoch 체크포인트를 선택했다. 2 epoch까지 학습했지만 test에는 선택된 모델만 평가했다. 이미지 모델은 4 epoch validation macro-F1이 0.8951이었고, 혼동행렬에서 셔츠↔티셔츠/상의·코트↔풀오버가 상대적으로 어려웠다. 학습 전 텍스트 모델의 분류 헤드는 무작위 초기화이므로, 이 개선 폭은 교육용 분류 과제의 학습 효과이며 외부 모델 품질 비교가 아니다.

- 텍스트 원본: `klue/klue` YNAT revision `349481ec73fff722f88e0453ca05c77a447d967c`; 모델 `klue/bert-base` revision `77c8b3d707df785034b4e50f2da5d37be5f0f546`.
- 이미지 원본: Zalando Fashion-MNIST 공식 저장소의 4개 gzip 파일. 각 파일의 MD5를 공식 문서 값과 비교했다. 원본 저장소의 `master`를 사용하되 내용은 MD5로 고정했다.
- 평가 지표의 근거: `.state/sat-8h/g6-results/text/comparison.json`, `.state/sat-8h/g6-results/image/comparison.json`, `.state/sat-8h/g6-results/image/confusion_matrix.json`.

## 추가 YNAT 전체 미세조정 코드 (사용자가 지목한 기존 예시와 별개)

- `labs/ynat-full-finetune/prepare.py`의 별도 번들을 준비하고 `train.py`를 수정 없이 Docker에서 `--mode smoke`로 실행했다.
- 70건 학습, 14건 평가, 5단계 전체 파라미터 업데이트. L4 최고 할당 메모리 9.317GB.
- 정확도 0% → 21.43%, macro-F1 0 → 0.1333, 잘못된 출력 비율 100% → 0%. backbone 가중치 변화와 CPU 체크포인트 재로딩이 통과했다.
- **14건 smoke 결과로 일반적인 품질 향상을 주장하지 않는다.** 역할은 기존 코드가 L4에서 학습·저장·재로딩까지 실행되는지 확인하는 것이다.
- 근거: `.state/sat-8h/g6-results/legacy/comparison.json`, `sat-ynat-legacy.log`.

## 비용·종료

Terraform 계획은 임시 자원 8개(EC2, 보안 그룹, 키 페어, S3 버킷·접근 제한, IAM 역할·정책·프로필) 생성이었다. 테스트 후 `aws-g6-practice/destroy-and-verify.sh`로 삭제하고 EC2·EBS·Terraform state를 검증한다. 삭제 확인 결과는 아래에 기록한다.

**삭제 확인:** `destroy-and-verify.sh` 완료. Terraform 8개 자원 삭제, EC2 `i-07a6cd01905928dd4` terminated, EBS `vol-056367e38a3b63b0e` deleted, Terraform state empty. 임시 S3 버킷도 Terraform에서 삭제됨.


## 사용자가 지목한 원본 LLM03 LoRA 별도 검증

- `owasp-llm-lab-setup-guide/examples/llm03`의 원본 `train_lora.py`, `infer_model.py`, 데이터 12행을 수정하지 않고 복사해 AWS us-east-1 `g6.xlarge`의 NVIDIA L4에서 실행했다.
- 모델은 `Qwen/Qwen2.5-0.5B-Instruct` revision `7ae557604adf67be50417f59c2c2f167def9a775`, 데이터 SHA256은 `68e27e462c6ba0168bd3f6aee86be89391a56e7a09e1e5673a489c4c5613dbd6`이다.
- 원본 설정대로 LoRA rank 16, 40단계를 학습했다. 실제 기록의 학습 손실은 약 1.0499, 학습 시간은 약 22.64초다. 기본 모델 응답에는 목표 문구가 없고, LoRA 적용 후 응답에는 목표 문구가 포함됐다. 이는 **모델 오염을 재현하는 보안 실습 출력**이지 실제 배포 승인·서명 검증 결과가 아니다.
- 원본 프로젝트의 GGUF 변환, 게시자·레지스트리·OpenBao를 포함한 전체 수명주기 테스트는 이 검증 범위에 포함되지 않는다.
- 출력 원본은 로컬 `.state/sat-8h/llm03/results`에 보존하며, 로컬 Training Job `llm03-qwen-lora-original-g6`의 평가 비교·로그·결과 파일에서 볼 수 있다. 원본 LoRA 가중치는 저장소에 커밋하지 않는다.
- 이 별도 테스트 후 Terraform 자원 8개가 삭제됐고 EC2 `i-0ea7d75306789ac8a` terminated, EBS `vol-0797647865a3ec5ad` deleted, Terraform state empty를 확인했다.
