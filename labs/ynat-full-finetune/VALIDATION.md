# 검증 기록

2026-10-23 작성 환경에서 수행:

- Python 파일 전체 AST 구문 검사 통과.
- 제목 정규화와 고정 프롬프트 검사 통과.
- 정답 전체 일치/전체 invalid/일부 invalid 입력에 대한 accuracy·macro-F1·invalid rate 검사 통과.
- 수정한 가이드의 shell 블록 17개: Bash 16개와 로컬 zsh 1개에 각각 `bash -n` / `zsh -n` 구문 검사 통과.

실행하지 않은 항목:

- Docker 빌드와 import 호환성 확인(작성 환경에 docker 명령 없음).
- Hugging Face 모델·데이터 다운로드 및 실제 표본 전처리.
- SCP CLI 실행, 계정 권한/스토리지/SCR/Training Job 생성.
- CUDA 학습, 저장 모델 재로딩, GPU 메모리/소요 시간/정확도/비용 측정.
- SCP의 종료 후 자원 회수 확인.

`run.py`의 프로세스 timeout과 기존 출력 디렉터리 거부는 코드에 포함되어 있지만, 실제 SCP에서 재시작/비용 차단 기능을 검증한 것은 아니다. 가이드의 smoke 실행을 첫 통합 검증으로 수행해야 한다.

추가: scripts/create-file-storage.sh 및 scripts/push-training-image.sh의 bash -n 검사 통과. 실제 CLI 생성 및 SCR push는 미실행.

2026-10-24 통합 경로 수정 검증:

- 실행 이미지에서 bundle COPY 및 기본 /opt/bundle 경로 제거.
- 모든 shell 스크립트와 가이드 Bash 블록 구문 검사 통과.
- run.py의 --bundle 누락 거부 확인. 파일시스템을 모의한 사전 검사에서 READY 누락/다른 릴리스 코드 거부 및 정상 릴리스 통과 확인.
- 이 통합 경로 수정 시점에는 실제 NFS·Docker·GPU 실행을 검증하지 않았다. File Storage Bad Request 원인도 미해결.

2026-10-24 runtime 의존성 수정 검증:

- 기존 로컬 이미지에는 NumPy 1.26.4와 PyArrow 26.0.0이 설치돼 `datasets` import가 실패했다.
- `Dockerfile.runtime`에 `pyarrow==18.1.0`을 고정하고 이미지 빌드 중 NumPy/PyArrow/Datasets/Transformers/PyTorch import 검사를 추가했다.
- `docker build --platform linux/amd64 -f Dockerfile.runtime -t sat-ynat-runtime:v1 .` 통과. 빌드 로그: `dependency imports ok: 1.26.4 18.1.0 3.1.0`.
- `docker run --rm --network none sat-ynat-runtime:v1`에서 패키지 import와 `prepare.py --help` 통과; 작은 `datasets.Dataset.from_dict` 테이블 생성도 통과.
- `pip check`는 베이스 이미지의 별도 `ninja 1.11.1.1 is not supported on this platform`를 보고해 빌드 게이트로 쓰지 않았다. 해당 검사만으로 PyArrow ABI 충돌도 잡지 못했다.
- 실제 `prepare.py --out /bundle` 실행으로 Qwen/Qwen2.5-0.5B와 KLUE YNAT 다운로드 및 오프라인 번들 생성 완료: `PASS: prepared offline bundle; no GPU used`. `manifest.json`의 train 1,400/dev 350/test 700행과 각 JSONL SHA-256을 확인했다.
- SCR push, SAT Job, CUDA 학습은 이번 검증에서 실행하지 않았다.
