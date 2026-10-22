#!/usr/bin/env bash
set -euo pipefail

# phase18a：在 phase17g-base（Phase16 + 修复后的 DBG2）基础上加入 Kona 最小 IORT（应用 SMMU + GPU SMMU 两个节点）。
# 目的：让 Windows 内核 IOMMU 初始化，使 qcsmmu8280 DriverEntry 中 IoGetIommuInterface 成功（Phase17j 实测为 0xC00000BB），
#       从而在 AddDevice 中跳过向 PEP 查询 {a0e1dd36} 的分支（PEP0 没有可用驱动）。
# IORT 由 tools/re/gen_kona_iort.py 生成：Alioth-Engineering/acpi/Kona-IORT-min.aml（参数来自 Linux v6.12 sm8250.dtsi）。
# 做法：构建期间放置 Silicium-ACPI/SoCs/Qualcomm/Kona/IORT.aml，并把 ACPI.inc 中注释掉的 IORT 行打开；
#       调用 build-acpi-hid-phase17f.sh（VARIANT=base，DBG2_FIX=1）完成构建；结束后恢复 ACPI.inc、删除临时 IORT。
# 说明：FVMAIN 的 NumBlocks=0（自动大小），日志里的"FVMAIN 100% Full"不代表空间不够；真正受限的是 FVMAIN_COMPACT（3MB）。

PROJECT_ROOT="${PROJECT_ROOT:-/home/ucchip/K40_Win11}"
MU_ROOT="${MU_ROOT:-$PROJECT_ROOT/sound_code/Mu-Silicium}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/UEFI-Images}"
TOOLS="$PROJECT_ROOT/Alioth-Engineering/tools"
LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_LOG="$LOG_DIR/mu-alioth-phase18a-build-$STAMP.log"
exec > >(tee "$BUILD_LOG") 2>&1
log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

IORT_SRC="$PROJECT_ROOT/Alioth-Engineering/acpi/Kona-IORT-min.aml"
IORT_SHA256="9af15bed2c8d14d6c165e4ec03c391ae32720c1c914e04ef433550a8890286f7"
KONA_IORT="$MU_ROOT/Silicium-ACPI/SoCs/Qualcomm/Kona/IORT.aml"
ACPI_INC="$MU_ROOT/Platforms/Xiaomi/aliothPkg/Include/ACPI.inc"

[ -f "$IORT_SRC" ] || { log "找不到 $IORT_SRC"; exit 1; }
[ -f "$ACPI_INC" ] || { log "找不到 $ACPI_INC"; exit 1; }
echo "$IORT_SHA256  $IORT_SRC" | sha256sum -c -
if [ -e "$KONA_IORT" ]; then log "$KONA_IORT 已存在（Silicium 原本没有 Kona IORT），请人工检查后再构建"; exit 1; fi

log "phase18a：Phase16 + 修复 DBG2 + Kona 最小 IORT，日志：$BUILD_LOG"

# 1. 放置 IORT、打开 ACPI.inc 中的 IORT 行（结束后恢复）
ACPI_INC_BAK="$ACPI_INC.pre-phase18a-$STAMP.bak"
cp -f "$ACPI_INC" "$ACPI_INC_BAK"
cleanup() {
    cp -f "$ACPI_INC_BAK" "$ACPI_INC"
    log "已恢复 ACPI.inc（备份 $ACPI_INC_BAK）"
    rm -f "$KONA_IORT"
    log "已删除临时 $KONA_IORT"
}
trap cleanup EXIT
cp -f "$IORT_SRC" "$KONA_IORT"
python3 - "$ACPI_INC" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read().replace('\r\n', '\n')
pat = re.compile(r'^#\s*SECTION RAW = Kona/IORT\.aml$', re.M)
if not pat.search(t):
    raise SystemExit('ACPI.inc 中找不到注释掉的 Kona/IORT.aml 行，请人工检查')
t = pat.sub('  SECTION RAW = Kona/IORT.aml', t)
open(p, 'w', encoding='utf-8').write(t)
print('ACPI.inc：已打开 Kona/IORT.aml')
PY
grep -n "IORT\|DBG2" "$ACPI_INC"

# 2. 调用 phase17f 脚本构建 base 变体（Phase16 DSDT + 修复 DBG2），产物放到临时目录
TMP_OUT="$(mktemp -d)"
VARIANT=base DBG2_FIX=1 OUTPUT_DIR="$TMP_OUT" PROJECT_ROOT="$PROJECT_ROOT" MU_ROOT="$MU_ROOT" bash "$TOOLS/build-acpi-hid-phase17f.sh"
BUILT="$(ls -t "$TMP_OUT"/*.img | head -1)"
[ -f "$BUILT" ] || { log "找不到构建产物"; exit 1; }

# 3. 确认 IORT 确实进了 FVMAIN
python3 - "$MU_ROOT/Build/aliothPkg" "$IORT_SRC" <<'PY'
import sys, pathlib
iort = pathlib.Path(sys.argv[2]).read_bytes()
hits = [str(f) for f in pathlib.Path(sys.argv[1]).rglob('*.Fv') if iort in f.read_bytes()]
print('包含 Kona IORT 的 FV：', hits)
if not any(h.endswith('FVMAIN.Fv') for h in hits):
    raise SystemExit('FVMAIN.Fv 中没有找到 IORT，镜像不可用')
PY
grep -E "FVMAIN_COMPACT \[" "$LOG_DIR"/mu-alioth-phase17g-base-build-*.log | tail -1 || true

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase18a-iort-dbg2-$STAMP.img"
cp -f "$BUILT" "$DEST"
rm -rf "$TMP_OUT"
log "镜像：$DEST"
sha256sum "$DEST"
log "手机端：fastboot boot（不要 flash）；kd 先监听，断点同 Phase17j（qcsmmu8280+0x2b1c 看 IoGetIommuInterface 返回值）。"
