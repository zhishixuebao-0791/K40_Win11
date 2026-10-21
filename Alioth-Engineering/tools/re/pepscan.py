import re, sys
lines = open(sys.argv[1], encoding='utf-8', errors='replace').read().split('\n')
i = 0
while i < len(lines):
    if re.match(r'^        (Scope\(\\_SB_\.PEP0\)|Device\(PEP0\))', lines[i]):
        start = i
        depth = 0
        j = i + 1
        while True:
            depth += lines[j].count('{') - lines[j].count('}')
            if depth == 0 and j > i + 1:
                break
            j += 1
        names = []
        for k in range(i + 1, j):
            m = re.match(r'^            (Method|Name)\((\w+)', lines[k])
            if m:
                names.append(m.group(2))
        # first DEVICE strings in block
        devs = sorted(set(re.findall(r'"\\\\_SB\.([\w.]+)"', '\n'.join(lines[i:j]))))
        print(f'{start+1}-{j+1}: {" ".join(names)} | devs: {" ".join(devs)[:200]}')
        i = j
    i += 1
