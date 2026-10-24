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
