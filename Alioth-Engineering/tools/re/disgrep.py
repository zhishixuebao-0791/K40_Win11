# 在 fulldis.py 生成的反汇编文本中检索：输出命中行所在函数及上下文
# 用法：python disgrep.py <反汇编.txt> <正则> [上文行数] [下文行数]
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().splitlines()
pat = re.compile(sys.argv[2]); b = int(sys.argv[3]) if len(sys.argv) > 3 else 0; a = int(sys.argv[4]) if len(sys.argv) > 4 else 0
cur = '?'; funcs = []
for l in lines:
    if l.startswith('sub_'): cur = l.rstrip(':')
    funcs.append(cur)
for i, l in enumerate(lines):
    if pat.search(l):
        print('[%s]' % funcs[i])
        for j in range(max(0, i - b), min(len(lines), i + a + 1)): print(('>> ' if j == i else '   ') + lines[j])
