# SAT Training Job 실습 · 20분 × 8차수

이 디렉터리는 **텍스트 1개, 이미지 1개**의 실제 학습 과제를 제공한다. 이전 YNAT 전체 미세조정 예시와 원본 LLM03 LoRA 예시는 별도 검증 기록으로 구분한다. 교육용 로컬/G6 컨테이너에서 입출력과 학습을 검증하고, SAT에서는 동일한 입력 번들·이미지·명령·결과 경로를 Job 필드에 매핑한다. AWS G6 결과를 SAT 자체에서 실행했다고 표현하지 않는다.

## 데이터와 모델

| 과제 | 공개 원본 | 입력 | 정답 | 모델 | 교육 평가 |
|---|---|---|---|---|---|
| 한국어 뉴스 분류 | KLUE YNAT, CC-BY-SA-4.0 | 한국어 제목 | 7개 한국어 주제 | klue/bert-base, CC-BY-SA-4.0 | 보관 test 700건 정확도·macro-F1 |
| 의류 이미지 분류 | Fashion-MNIST, MIT | 28×28 회색조 이미지 | 10개 의류 종류(표시명 한국어) | 소형 PyTorch CNN | 보관 test 2,000건 정확도·macro-F1 |

KLUE 데이터는 [공식 데이터셋 카드](https://huggingface.co/datasets/klue/klue/blob/main/README.md), 모델은 [KLUE BERT 카드](https://huggingface.co/klue/bert-base)를 따른다. Fashion-MNIST 데이터·라벨·MD5·라이선스는 [Zalando 공식 저장소](https://github.com/zalandoresearch/fashion-mnist)를 따른다. 공개 데이터를 재배포할 때 각 라이선스와 출처를 함께 제공한다. 이미지 라벨의 한국어 표기는 수업용 번역이다.

## 입력과 결과

`prepare.py`가 공개 원본을 다운로드하고 원본 해시, 중복, 클래스 균형, 분리된 train/val/test 및 SHA256 매니페스트를 만든다. 실제 샘플 형식은 [text.jsonl](samples/text.jsonl)과 [images](samples/images)에 있다. 모델과 전체 데이터 번들은 저장소의 무시된 `.state/sat-8h/bundle`에 보관한다.

`train_text.py`, `train_image.py`는 모두 **학습 전 test → train/val → 최적 체크포인트 재로딩 → 같은 test의 학습 후 평가**를 기록한다. 출력은 각각 `comparison.json`, `before.json`, `after.json`, 에포크별 validation, 모델 가중치이며 이미지 과제는 `confusion_matrix.json`도 만든다. 학습 전의 텍스트 분류 헤드는 무작위 초기화되므로 이 비교는 수업용 학습 효과 검증이다. 공식 KLUE 점수와 비교하지 않는다.

## 로컬 CPU 준비

```bash
docker build -t sat-8h:local labs/sat-8h
mkdir -p .state/sat-8h/bundle
docker run --rm -v "$PWD/.state/sat-8h/bundle:/bundle" sat-8h:local \
  python /lesson/prepare.py --out /bundle --task all
```

재실행할 때 이미 존재하는 매니페스트는 덮어쓰지 않는다. 새 번들을 만들거나 기존 검증된 번들을 사용한다.

검증된 2026-11-05 실행 결과는 [RESULTS.md](RESULTS.md), 160분 시간표는 [CURRICULUM.md](CURRICULUM.md), 차수별 강의 스크립트·실습은 [TEACHING_GUIDE.md](TEACHING_GUIDE.md), 발표용 교안 화면은 [SLIDE_DECK.md](SLIDE_DECK.md)에 있다.

## 단일 G6 컨테이너 실습

Terraform 작업 디렉터리는 `aws-g6-practice/`이다. 준비된 번들과 코드를 SSH로 전송하고 G6의 NVIDIA Container Toolkit이 설정된 뒤 다음처럼 실행한다.

```bash
docker build -t sat-8h:local /home/ubuntu/sat-8h
mkdir -p /home/ubuntu/sat-8h-output
docker run --rm --gpus all --shm-size 2g \
  -v /home/ubuntu/sat-8h-bundle:/bundle:ro \
  -v /home/ubuntu/sat-8h-output:/output \
  sat-8h:local /lesson/run_all.sh
```

GPU가 없는 로컬 환경에서 학습 스크립트를 실행하지 않는다. 결과 수집 후 `aws-g6-practice/destroy-and-verify.sh`로 Terraform 인스턴스와 임시 디스크·버킷을 제거하고 실제 종료를 확인한다.

## 별도 검증한 예시

`labs/ynat-full-finetune/`의 Qwen2.5-0.5B **전체 미세조정**은 별도 과제이다. 현재 새 한국어 분류 실습과 같은 YNAT 원본을 쓰지만 프롬프트 기반 생성형 분류와 전체 파라미터 업데이트를 보여 준다. `check_offline.py`는 CPU의 구문·지표 검증이며 GPU 학습 성공을 뜻하지 않는다. G6에서 실행할 때는 이전 `prepare.py`로 만든 별도 번들을 사용한다.


사용자가 지목한 이전 예시는 owasp-llm-lab-setup-guide/examples/llm03의 원본 Qwen2.5-0.5B LoRA 코드다. 원본 데이터·코드를 복사해 AWS G6에서 40단계 학습과 학습 전후 추론을 검증했다. 로컬 Job 목록에는 llm03-qwen-lora-original-g6로 게시했다. 이는 160분 필수 과정이 아닌 보안 심화 시연이다. 원본 프로젝트의 전체 배포·GGUF·레지스트리 수명주기를 검증했다는 뜻은 아니다.
