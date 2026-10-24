"""CPU-only helpers used by preparation, training, and offline checks."""
import unicodedata

LABELS = ['IT과학', '경제', '사회', '생활문화', '세계', '스포츠', '정치']

def normalize(text):
    return ' '.join(unicodedata.normalize('NFKC', text).split())

def prompt(title):
    return ('뉴스 제목의 주제를 IT과학, 경제, 사회, 생활문화, 세계, 스포츠, 정치 중 '
            '하나로 분류하세요. 주제 이름만 답하세요.\n뉴스 제목: ' + title + '\n분류:')

def score(gold, pred):
    assert len(gold) == len(pred) and gold
    f1s = []
    for k in range(7):
        tp = sum(g == k and p == k for g, p in zip(gold, pred))
        fp = sum(g != k and p == k for g, p in zip(gold, pred))
        fn = sum(g == k and p != k for g, p in zip(gold, pred))
        f1s.append(2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0)
    return dict(n=len(gold), accuracy=sum(g == p for g, p in zip(gold, pred))/len(gold),
                macro_f1=sum(f1s)/7, invalid_rate=sum(p == -1 for p in pred)/len(pred))
