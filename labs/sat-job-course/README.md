# SAT 중심 Training Job 과정

이 디렉터리는 **20분 × 8차수, 총 160분**의 새 교안이다. 이전 텍스트·이미지 모델 중심 과정은 [`../sat-8h/`](../sat-8h/)에 백업으로 남긴다. 새 과정은 SCP Simple AI Training(SAT)의 Job 설정, 입력·출력 연결, 상태·로그·결과 읽기, Spot 운영 판단에 집중한다. AWS SageMaker AI Training Job과 Amazon Bedrock 파인튜닝은 실무 비교 사례로 사용한다.

| 파일 | 용도 |
|---|---|
| [CURRICULUM.md](CURRICULUM.md) | 8차수 시간표와 수료 기준 |
| [SAT Training Job 과정 기획안.xlsx](outputs/01a1a667-e6a3-79d3-bb94-7717b08ece3b/SAT_Training_Job_과정_기획안.xlsx) | 제공된 Simple AI Inference 기획안의 시트·열·서식을 따른 8차수 Excel |
| [TEACHING_GUIDE.md](TEACHING_GUIDE.md) | 5분 단위 강사 발화·화면 시연·학습자 실습·정답 |
| [SLIDE_DECK.md](SLIDE_DECK.md) | 발표 화면에 바로 옮길 수 있는 교안 원고 |
| [SERVICE_COMPARISON.md](SERVICE_COMPARISON.md) | SAT·SageMaker·Bedrock 실무 비교와 출처 |

## 수업의 실제 환경

- [로컬 Training Job 화면](http://127.0.0.1:8080/local#jobs)은 사용자가 저장한 SCP 화면을 참고해 만든 교육용 사이트다. 보존된 AWS G6 실행 기록을 조회할 수 있지만 SCP SAT에서 새 Job을 실행했다는 증거는 아니다.
- [원본 demo Job](http://127.0.0.1:8080/local#jobs/b669419947d55d6991620cdf9bbcaa1f/details), [한국어 YNAT Job](http://127.0.0.1:8080/local#jobs/2dd8760c5b7b55dc8d440c0d18ad2a4e/details), [이미지 Job](http://127.0.0.1:8080/local#jobs/cb0e433e77965ac9ad283d14027ed2df/details)을 자료로 쓴다.
- `scp_sat_videos/`의 상품설명회·아키텍처 강의 전사는 **SAT 개념·상품 발화 근거**다. 현재 제공 기능과 가격은 제품 문서·실제 콘솔에서 따로 확인한다.
- 이 과정에서는 GPU Job을 새로 실행하거나 EC2를 생성하지 않는다. 실습은 설정 화면 작성, 저장된 Job 조회, 파일·로그 판독이다.
