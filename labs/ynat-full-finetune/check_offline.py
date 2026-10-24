"""No third-party packages, network, or GPU needed. Not a training test."""
import ast
from pathlib import Path
from common import LABELS, normalize, prompt, score

root = Path(__file__).parent
for file in root.glob('*.py'):
    ast.parse(file.read_text(), filename=str(file))
assert normalize('Ａ  뉴스\n제목') == 'A 뉴스 제목'
assert '정답' not in prompt('테스트 제목')
assert all(name in prompt('제목') for name in LABELS)
assert score(list(range(7)), list(range(7))) == dict(n=7, accuracy=1, macro_f1=1, invalid_rate=0)
invalid = score(list(range(7)), [-1]*7)
assert invalid['accuracy'] == 0 and invalid['macro_f1'] == 0 and invalid['invalid_rate'] == 1
# Invalid output must count as a false negative for the true class.
mixed = score([0,0,1,2,3,4,5,6], [0,-1,1,2,3,4,5,6])
assert abs(mixed['macro_f1'] - (2/3+6)/7) < 1e-10
assert mixed['accuracy'] == 7/8
print('PASS: Python syntax, normalization, prompt, metrics including invalid outputs')
print('NOT TESTED: Docker build, downloads, SCP, CUDA, training quality, billing')
