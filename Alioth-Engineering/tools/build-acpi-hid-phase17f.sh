#!/usr/bin/env bash
set -euo pipefail

# phase17f：在 RELEASE 构建中强制打包 Kona/DBG2.aml，供 KDNET over USB EEM（kd_8003_5143.dll）内核调试使用。
# 原因：aliothPkg/Include/ACPI.inc 中 DBG2 只在 `!if $(TARGET) == DEBUG` 时打包，而 build_uefi.sh 默认 TARGET=RELEASE，
#       之前所有镜像都没有 DBG2，winload 找不到调试设备，KD 传输模块根本没加载（手机上没有 Services\kdnet）。
#
# VARIANT=pep （默认）：沿用 Ubuntu 上现有的叠加 DSDT 状态，调用 build-acpi-hid-phase17e.sh（PEP_STUB=all），即 17e-all + DBG2。
# VARIANT=base：用 Phase17 脚本留下的最早一份 DSDT.asl.pre-phase17-*.bak（Phase16 状态）直接编译，即 Phase16 + DBG2，排障备用。
#
# 注意：这两个构建脚本都不能从 Silicium-ACPI 原始 DSDT 开始（依赖更早阶段叠加的修改），所以不要 git checkout DSDT.asl。

PROJECT_ROOT="${PROJECT_ROOT:-/home/ucchip/K40_Win11}"
MU_ROOT="${MU_ROOT:-$PROJECT_ROOT/sound_code/Mu-Silicium}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/UEFI-Images}"
VARIANT="${VARIANT:-pep}"
case "$VARIANT" in
    pep|base) ;;
    *) echo "VARIANT 只能是 pep / base"; exit 1 ;;
esac
# phase17g：DBG2_FIX=1（默认）在构建期间用 Alioth-Engineering/acpi/Kona-DBG2-oemfix.aml 替换 Silicium 的 Kona/DBG2.aml。
# Silicium 原表的 OEM 区错位（装的是表头前 0x94 字节），2XIF 修补（强制 VBUS 有效 QSCRATCH HS_PHY_CTRL=0x10100000 等）失效，
# DWC3 不上拉，KD 卡在 KdUsbFnWaitForConnection（Phase17f-base 实测停在 Silicium 画面）。修复表由 tools/re/fix_kona_dbg2.py 生成。
DBG2_FIX="${DBG2_FIX:-1}"
if [ "$DBG2_FIX" = "1" ]; then PHASE_TAG="phase17g"; else PHASE_TAG="phase17f"; fi
FIXED_DBG2_SHA256="b49338c28cdaa96773cc71798e191859c9212f4d5d3da5fc428d6c4bd601b200"

TOOLS="$PROJECT_ROOT/Alioth-Engineering/tools"
LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_LOG="$LOG_DIR/mu-alioth-${PHASE_TAG}-${VARIANT}-build-$STAMP.log"
exec > >(tee "$BUILD_LOG") 2>&1

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

ACPI_INC="$MU_ROOT/Platforms/Xiaomi/aliothPkg/Include/ACPI.inc"
ALIOTH_ACPI="$MU_ROOT/Silicium-ACPI/Platforms/Xiaomi/alioth"
KONA_DBG2="$MU_ROOT/Silicium-ACPI/SoCs/Qualcomm/Kona/DBG2.aml"
for f in "$ACPI_INC" "$ALIOTH_ACPI/DSDT.asl" "$KONA_DBG2"; do
    [ -f "$f" ] || { log "找不到 $f"; exit 1; }
done

log "$PHASE_TAG 变体：$VARIANT，DBG2_FIX=$DBG2_FIX，日志：$BUILD_LOG"

# 1. 让 DBG2 在 RELEASE 中也打包（构建结束后恢复原 ACPI.inc）；DBG2_FIX=1 时同时换上修复后的 Kona DBG2（结束后恢复）
ACPI_INC_BAK="$ACPI_INC.pre-phase17f-$STAMP.bak"
cp -f "$ACPI_INC" "$ACPI_INC_BAK"
KONA_DBG2_BAK="$KONA_DBG2.pre-$PHASE_TAG-$STAMP.bak"
cp -f "$KONA_DBG2" "$KONA_DBG2_BAK"
restore_sources() {
    cp -f "$ACPI_INC_BAK" "$ACPI_INC"
    log "已恢复 ACPI.inc（备份 $ACPI_INC_BAK）"
    cp -f "$KONA_DBG2_BAK" "$KONA_DBG2"
    log "已恢复 Kona/DBG2.aml（备份 $KONA_DBG2_BAK）"
}
trap restore_sources EXIT

if [ "$DBG2_FIX" = "1" ]; then
    FIXED_DBG2="$PROJECT_ROOT/Alioth-Engineering/acpi/Kona-DBG2-oemfix.aml"
    [ -f "$FIXED_DBG2" ] || { log "找不到 $FIXED_DBG2"; exit 1; }
    echo "$FIXED_DBG2_SHA256  $FIXED_DBG2" | sha256sum -c -
    cp -f "$FIXED_DBG2" "$KONA_DBG2"
    log "已换上修复后的 Kona DBG2（OEM 区为 2XIF 修补表）"
fi
python3 - "$KONA_DBG2" "$DBG2_FIX" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
off, num = struct.unpack_from('<II', d, 36)
p = off
_, ln, _, nsl, nso, oeml, oemo, pt, pst = struct.unpack_from('<BHBHHHHHH', d, p)
o = d[p + oemo:p + oemo + oeml]
print(f'DBG2：校验和 {sum(d) % 256}（应为 0），设备数 {num}，类型 {pt:#x}/{pst:#x}，OEM+4 = {o[4:8]!r}')
if sum(d) % 256:
    raise SystemExit('DBG2 校验和错误')
if sys.argv[2] == '1' and o[4:8] != b'2XIF':
    raise SystemExit('DBG2 OEM 区没有 2XIF 签名，修复未生效')
PY

python3 - "$ACPI_INC" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read().replace('\r\n', '\n')
pat = re.compile(r'!if \$\(TARGET\) == DEBUG\n(\s*SECTION RAW = Kona/DBG2\.aml\n)!endif\n')
if pat.search(t):
    t = pat.sub(r'\1', t)
    print('ACPI.inc：已去掉 DBG2 的 DEBUG 条件')
elif re.search(r'^\s*SECTION RAW = Kona/DBG2\.aml$', t, re.M):
    print('ACPI.inc：DBG2 已经是无条件打包，跳过')
else:
    raise SystemExit('ACPI.inc 中找不到 Kona/DBG2.aml 这一行，请人工检查')
if re.search(r'^\s*#\s*SECTION RAW = Kona/DBG2', t, re.M):
    raise SystemExit('ACPI.inc 中 DBG2 被注释掉了，请人工检查')
open(p, 'w', encoding='utf-8').write(t)
PY
grep -n "DBG2\|!if\|!endif" "$ACPI_INC"

# 2. 生成 DSDT 并构建
if [ "$VARIANT" = "pep" ]; then
    log "调用 build-acpi-hid-phase17e.sh（PEP_STUB=all）"
    TMP_OUT="$(mktemp -d)"
    PEP_STUB=all OUTPUT_DIR="$TMP_OUT" PROJECT_ROOT="$PROJECT_ROOT" MU_ROOT="$MU_ROOT" bash "$TOOLS/build-acpi-hid-phase17e.sh"
    BUILT="$(ls -t "$TMP_OUT"/*.img | head -1)"
else
    BAK="$(ls -tr "$ALIOTH_ACPI"/DSDT.asl.pre-phase17-*.bak 2>/dev/null | head -1 || true)"
    [ -n "$BAK" ] || { log "找不到 DSDT.asl.pre-phase17-*.bak"; exit 1; }
    log "使用 Phase16 状态的 DSDT 备份：$BAK"
    python3 - "$BAK" <<'PY'
import sys
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
checks = {
    'SMMU 为 QCOM2509（Phase16）': t.count('"QCOM2509"') == 2,
    'PEP0 仍为 QCOM0519（未进入 Phase17）': t.count('"QCOM0519"') == 1 and '"QCOM2519"' not in t,
    'PEPH 仍为 DEV_0519': 'DEV_0519' in t and 'DEV_2519' not in t,
    '没有 phase17e 桩': '// phase17e-stub' not in t,
    'PILC 已含 MTP08280': 'MTP08280' in t,
}
for k, v in checks.items():
    print(f'{k}: {v}')
    if not v:
        raise SystemExit(f'备份不是 Phase16 状态：{k}')
PY
    cp -f "$ALIOTH_ACPI/DSDT.asl" "$ALIOTH_ACPI/DSDT.asl.pre-phase17f-base-$STAMP.bak"
    cp -f "$BAK" "$ALIOTH_ACPI/DSDT.asl"
    log "编译 DSDT.asl（iasl -f）"
    ( cd "$ALIOTH_ACPI" && iasl -f -ve -p DSDT DSDT.asl )
    export CLANG_BIN="$PROJECT_ROOT/tools/linux-bin/"
    export PATH="$PROJECT_ROOT/tools/linux-bin:$PATH"
    ( cd "$MU_ROOT" && bash ./build_uefi.sh -d alioth -m 1 -i -c )
    BUILT="$MU_ROOT/Mu-alioth-1.img"
    # 恢复为构建前的叠加状态，不影响后续 17e/17f pep 构建
    cp -f "$ALIOTH_ACPI/DSDT.asl.pre-phase17f-base-$STAMP.bak" "$ALIOTH_ACPI/DSDT.asl"
    log "已把 DSDT.asl 恢复为构建前状态"
fi
[ -f "$BUILT" ] || { log "找不到构建产物 $BUILT"; exit 1; }

# 3. 确认 DBG2 确实进了固件卷（解压前的 FV 中应能找到 Kona DBG2 原始字节）
python3 - "$MU_ROOT/Build/aliothPkg" "$KONA_DBG2" <<'PY'
import sys, pathlib
dbg2 = pathlib.Path(sys.argv[2]).read_bytes()
hits = []
for fv in pathlib.Path(sys.argv[1]).rglob('*'):
    if fv.is_file() and fv.suffix.lower() in ('.fv', '.ffs', '.raw', '.bin') and fv.stat().st_size < 64 * 1024 * 1024:
        if dbg2 in fv.read_bytes():
            hits.append(str(fv))
print('包含 Kona DBG2 的构建文件：')
for h in hits[:10]:
    print('  ', h)
if not any(h.lower().endswith('.fv') for h in hits):
    raise SystemExit('FV 中没有找到 DBG2，镜像不可用')
PY

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-${PHASE_TAG}-${VARIANT}-dbg2-$STAMP.img"
cp -f "$BUILT" "$DEST"
log "镜像：$DEST"
sha256sum "$DEST"
log "手机端：fastboot boot（不要 flash）；BCD 已设 debug on、busparams 0（DBG2 中唯一的设备）、key 1.2.3.4、port 50005。"
