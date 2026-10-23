#!/usr/bin/env bash
set -euo pipefail

# phase19（在 Ubuntu 构建机上运行）：在 phase17g-base（Phase16 DSDT + 修复版 Kona DBG2，供 KDNET）基础上，
#   从 Device(UFS0) 删除 _DEP(\_SB.PEP0)。
# 原因（dead-ends 死路17/突破15）：UFS0 的 _DEP 让 Windows 把 PEP0 当引导前置；一旦给 PEP0 分配 pep0stub 驱动，
#   UFS 会死等 PEP0 启动 → 0x7B(0xC0000034)。去掉后 UFS 不再等 PEP0，pep0stub 可用 Start=1 由内核开机后加载
#   （内核 CI 认已导入的测试证书），再向 Start=3 的 qcsmmu 提供 {55beca03}。
# 本脚本基于 build-acpi-hid-phase17f.sh 的 base 分支，仅在 iasl 编译前插入 patch-dsdt-remove-ufs-pep-dep.py。

PROJECT_ROOT="${PROJECT_ROOT:-/home/ucchip/K40_Win11}"
MU_ROOT="${MU_ROOT:-$PROJECT_ROOT/sound_code/Mu-Silicium}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/UEFI-Images}"
PHASE_TAG="phase19"
FIXED_DBG2_SHA256="b49338c28cdaa96773cc71798e191859c9212f4d5d3da5fc428d6c4bd601b200"

TOOLS="$PROJECT_ROOT/Alioth-Engineering/tools"
LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_LOG="$LOG_DIR/mu-alioth-${PHASE_TAG}-build-$STAMP.log"
exec > >(tee "$BUILD_LOG") 2>&1
log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

ACPI_INC="$MU_ROOT/Platforms/Xiaomi/aliothPkg/Include/ACPI.inc"
ALIOTH_ACPI="$MU_ROOT/Silicium-ACPI/Platforms/Xiaomi/alioth"
KONA_DBG2="$MU_ROOT/Silicium-ACPI/SoCs/Qualcomm/Kona/DBG2.aml"
PATCHER="$TOOLS/patch-dsdt-remove-ufs-pep-dep.py"
for f in "$ACPI_INC" "$ALIOTH_ACPI/DSDT.asl" "$KONA_DBG2" "$PATCHER"; do
    [ -f "$f" ] || { log "找不到 $f"; exit 1; }
done
log "$PHASE_TAG 构建，日志：$BUILD_LOG"

# 1. DBG2：RELEASE 也打包 + 换修复表（结束恢复）
ACPI_INC_BAK="$ACPI_INC.pre-phase19-$STAMP.bak"; cp -f "$ACPI_INC" "$ACPI_INC_BAK"
KONA_DBG2_BAK="$KONA_DBG2.pre-phase19-$STAMP.bak"; cp -f "$KONA_DBG2" "$KONA_DBG2_BAK"
restore_sources() {
    cp -f "$ACPI_INC_BAK" "$ACPI_INC"; log "已恢复 ACPI.inc"
    cp -f "$KONA_DBG2_BAK" "$KONA_DBG2"; log "已恢复 Kona/DBG2.aml"
}
trap restore_sources EXIT

FIXED_DBG2="$PROJECT_ROOT/Alioth-Engineering/acpi/Kona-DBG2-oemfix.aml"
[ -f "$FIXED_DBG2" ] || { log "找不到 $FIXED_DBG2"; exit 1; }
echo "$FIXED_DBG2_SHA256  $FIXED_DBG2" | sha256sum -c -
cp -f "$FIXED_DBG2" "$KONA_DBG2"
log "已换上修复后的 Kona DBG2"
python3 - "$ACPI_INC" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding='utf-8').read().replace('\r\n', '\n')
pat = re.compile(r'!if \$\(TARGET\) == DEBUG\n(\s*SECTION RAW = Kona/DBG2\.aml\n)!endif\n')
if pat.search(t):
    t = pat.sub(r'\1', t); print('ACPI.inc：已去掉 DBG2 的 DEBUG 条件')
elif re.search(r'^\s*SECTION RAW = Kona/DBG2\.aml$', t, re.M):
    print('ACPI.inc：DBG2 已无条件打包，跳过')
else:
    raise SystemExit('ACPI.inc 中找不到 Kona/DBG2.aml 行')
open(p, 'w', encoding='utf-8').write(t)
PY

# 2. 取 Phase16 状态 DSDT（与 17f-base 相同），校验，复制为当前 DSDT.asl
BAK="$(ls -tr "$ALIOTH_ACPI"/DSDT.asl.pre-phase17-*.bak 2>/dev/null | head -1 || true)"
[ -n "$BAK" ] || { log "找不到 DSDT.asl.pre-phase17-*.bak"; exit 1; }
log "使用 Phase16 状态 DSDT：$BAK"
python3 - "$BAK" <<'PY'
import sys
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
checks = {
    'SMMU 为 QCOM2509（Phase16）': t.count('"QCOM2509"') == 2,
    'PEP0 仍为 QCOM0519': t.count('"QCOM0519"') == 1 and '"QCOM2519"' not in t,
    'PILC 已含 MTP08280': 'MTP08280' in t,
}
for k, v in checks.items():
    print(f'{k}: {v}')
    if not v: raise SystemExit(f'备份不是 Phase16 状态：{k}')
PY
cp -f "$ALIOTH_ACPI/DSDT.asl" "$ALIOTH_ACPI/DSDT.asl.pre-phase19-$STAMP.bak"
cp -f "$BAK" "$ALIOTH_ACPI/DSDT.asl"

# 3. 关键：删除 UFS0 的 _DEP(\_SB.PEP0)
log "应用补丁：删除 UFS0 的 _DEP(\\_SB.PEP0)"
python3 "$PATCHER" "$ALIOTH_ACPI/DSDT.asl"

# 4. 编译 + 构建（与 17f-base 相同，iasl -f 容忍反编译残留错误）
log "编译 DSDT.asl（iasl -f）"
( cd "$ALIOTH_ACPI" && iasl -f -ve -p DSDT DSDT.asl )
export CLANG_BIN="$PROJECT_ROOT/tools/linux-bin/"
export PATH="$PROJECT_ROOT/tools/linux-bin:$PATH"
( cd "$MU_ROOT" && bash ./build_uefi.sh -d alioth -m 1 -i -c )
BUILT="$MU_ROOT/Mu-alioth-1.img"
cp -f "$ALIOTH_ACPI/DSDT.asl.pre-phase19-$STAMP.bak" "$ALIOTH_ACPI/DSDT.asl"
log "已把 DSDT.asl 恢复为构建前状态"
[ -f "$BUILT" ] || { log "找不到构建产物 $BUILT"; exit 1; }

# 5. 确认 DBG2 进了固件卷
python3 - "$MU_ROOT/Build/aliothPkg" "$KONA_DBG2" <<'PY'
import sys, pathlib
dbg2 = pathlib.Path(sys.argv[2]).read_bytes(); hits = []
for fv in pathlib.Path(sys.argv[1]).rglob('*'):
    if fv.is_file() and fv.suffix.lower() in ('.fv', '.ffs', '.raw', '.bin') and fv.stat().st_size < 64*1024*1024:
        if dbg2 in fv.read_bytes(): hits.append(str(fv))
print('包含 Kona DBG2 的构建文件：'); [print('  ', h) for h in hits[:10]]
if not any(h.lower().endswith('.fv') for h in hits): raise SystemExit('FV 中没有 DBG2')
PY

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-${PHASE_TAG}-noufsdep-dbg2-$STAMP.img"
cp -f "$BUILT" "$DEST"
log "镜像：$DEST"; sha256sum "$DEST"
log "手机端：fastboot boot（不要 flash）。pep0stub 保持 Start=1。"
