#!/usr/bin/env python3
# Phase19：从 alioth DSDT.asl 的 Device(UFS0) 中删除 _DEP(\_SB.PEP0)。
# 目的：UFS0 是引导设备，其 _DEP 让 Windows 把 PEP0 当成启动前置；一旦给 PEP0 分配了
#   驱动(pep0stub)，UFS 会死等 PEP0 启动 → 0x7B(0xC0000034)。去掉这个 _DEP 后 UFS 不再等
#   PEP0，pep0stub 可用 Start=1 由内核在开机后加载（死路17 / 突破15）。
# 只动 Device(UFS0) 内的第一个 _DEP；SDC2/ABD_ 等对 PEP0 的 _DEP 不动（非引导设备，不阻塞）。
# 用法：python3 patch-dsdt-remove-ufs-pep-dep.py <DSDT.asl>   （原地修改，先写 .pre-phase19.bak）
import re, sys, shutil

if len(sys.argv) != 2:
    sys.exit("用法：patch-dsdt-remove-ufs-pep-dep.py <DSDT.asl>")
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()

# 定位 Device(UFS0) 块起点
m = re.search(r'Device\s*\(\s*UFS0\s*\)', text)
if not m:
    sys.exit("找不到 Device(UFS0)")
start = m.end()

# 在 UFS0 块内找第一个 _DEP（限定在 UFS0 到下一个同级 Device( 之间）
nxt = re.search(r'\n\s*Device\s*\(', text[start:])
region_end = start + (nxt.start() if nxt else len(text) - start)
region = text[start:region_end]

dep = re.search(
    r'[ \t]*Name\s*\(\s*_DEP\s*,\s*Package\s*\([^)]*\)\s*\{\s*\\_SB_?\.PEP0\s*\}\s*\)\s*\n',
    region)
if not dep:
    sys.exit("UFS0 内找不到引用 \\_SB.PEP0 的 _DEP（可能已被改过，请人工检查）")

removed = region[dep.start():dep.end()]
new_region = region[:dep.start()] + region[dep.end():]

# 安全校验：UFS0 内只应删一处；确保删的确实含 PEP0
if '\\_SB_.PEP0' not in removed and '\\_SB.PEP0' not in removed:
    sys.exit("内部错误：待删块不含 PEP0")

new_text = text[:start] + new_region + text[region_end:]

# PEP0 在整文件的其它 _DEP（SDC2/ABD_ 等）应保持不变
before_pep0 = text.count('\\_SB_.PEP0') + text.count('\\_SB.PEP0')
after_pep0 = new_text.count('\\_SB_.PEP0') + new_text.count('\\_SB.PEP0')
if before_pep0 - after_pep0 != 1:
    sys.exit(f"PEP0 引用数变化异常：{before_pep0} -> {after_pep0}（应恰好 -1）")

shutil.copyfile(path, path + ".pre-phase19.bak")
open(path, "w", encoding="utf-8").write(new_text)
print("已删除 UFS0 的 _DEP(\\_SB.PEP0)：")
print("".join("    " + l + "\n" for l in removed.strip("\n").splitlines()))
print(f"PEP0 引用：{before_pep0} -> {after_pep0}（其余 _DEP 未动）；备份 {path}.pre-phase19.bak")
