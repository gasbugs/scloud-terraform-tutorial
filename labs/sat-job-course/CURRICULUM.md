# SAT Training Job · 20분 × 8차수

**총 160분.** 1·5차수는 이론, 나머지 6차수는 화면·결과 중심 실습이다. YNAT와 Fashion-MNIST는 모델 학습법을 가르치는 대상이 아니라 서로 다른 Job 산출물 사례다.

| 차수 | 시간 | 구분 | SAT 중심 주제 | 학습자가 남길 증거 |
|---:|---:|---|---|---|
| 1 | 0–20분 | 이론 | SAT의 관리형 Job, EC2 직접 운영과의 차이, SageMaker·Bedrock의 위치 | 세 서비스 선택 기준 1문장 |
| 2 | 20–40분 | 실습 | 입력 데이터·코드/이미지·명령·스토리지 경로를 Job에 매핑 | 원본 demo 입출력 경로표 |
| 3 | 40–60분 | 실습 | On-Demand Training Job 생성 화면의 필수 옵션과 요약 검토 | 제출 전 설정표 |
| 4 | 60–80분 | 실습 | Spot Training Job 생성 화면, 대기·중단·Failover 표시 확인 | On-Demand/Spot 차이표 |
| 5 | 80–100분 | 이론 | Job 상태 전이, 모니터링·로그·체크포인트·결과 저장의 역할 | 증거 확인 순서도 |
| 6 | 100–120분 | 실습 | 원본 demo와 텍스트 Job의 상세·상태·로그 판독 | 상태와 로그 근거 3개 |
| 7 | 120–140분 | 실습 | 결과 파일·평가 비교·모니터링 기록의 유무 확인 | 결과 판독표 |
| 8 | 140–160분 | 실습 | SAT·SageMaker·Bedrock 실무 선택, 운영·비용·이동성 판단 | 1쪽 서비스 선택 메모 |

## 수료 기준

1. SAT Job의 입력 원본, 컨테이너 내부 경로, Command, 출력 위치를 혼동하지 않는다.
2. Spot의 유휴 자원·대기·중단 가능성과 생성 화면의 **Job Failover 사용 불가 표시**를 설명한다. 일반 GPU 장애 복구와 Spot 회수 후 재개를 별개로 설명한다.
3. `Completed`를 성능 향상과 동일시하지 않고 로그·평가·모델 파일로 판단한다. GPU 시계열이 없는 가져온 기록은 `없음`으로 표시한다.
4. SAT·SageMaker·Bedrock 중 요구사항에 적합한 서비스를 근거와 함께 선택한다.

자세한 발화·실습은 [TEACHING_GUIDE.md](TEACHING_GUIDE.md), 발표 화면은 [SLIDE_DECK.md](SLIDE_DECK.md), 제품 비교의 근거는 [SERVICE_COMPARISON.md](SERVICE_COMPARISON.md)에 있다.
