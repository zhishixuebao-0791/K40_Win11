#!/usr/bin/env bash
set -euo pipefail

# phase17h：实测 Surface WHQL 的 qcpep8280.sys 能否在 SM8250 上工作。
#   在 Ubuntu 上当前的叠加 DSDT（17e-all 状态：PEP0=QCOM2519、PEPH=DEV_2519、UFS0 无 _DEP、27 个设备配置方法清空）基础上，
#   只把 PEP0 的 _HID 与 PEPH 返回值改为 0617（qcpep.wd8280.inf 认 ACPI\QCOM0617），其余不动；
#   同时像 17g 一样打包修复后的 DBG2（acpi/Kona-DBG2-oemfix.aml），便于 KDNET 调试。
#   构建结束后恢复 DSDT.asl、ACPI.inc、Kona/DBG2.aml，不影响 17e/17f/17g 的重复构建。
# 背景：qcpep8250 在 AddDevice 中写 SM8150 的 LMH 0x18350800/0x18358800，SM8250 上不存在，CPU7 卡死（Phase17g 现场确认）；
#       qcpep8280 不含这些地址，CPU 调频用 EPSS 0x18591000/0x18592000，与 SM8250 一致。

PROJECT_ROOT="${PROJECT_ROOT:-/home/ucchip/K40_Win11}"
MU_ROOT="${MU_ROOT:-$PROJECT_ROOT/sound_code/Mu-Silicium}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/UEFI-Images}"
FIXED_DBG2_SHA256="b49338c28cdaa96773cc71798e191859c9212f4d5d3da5fc428d6c4bd601b200"

LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_LOG="$LOG_DIR/mu-alioth-phase17h-build-$STAMP.log"
exec > >(tee "$BUILD_LOG") 2>&1
log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

ACPI_INC="$MU_ROOT/Platforms/Xiaomi/aliothPkg/Include/ACPI.inc"
ALIOTH_ACPI="$MU_ROOT/Silicium-ACPI/Platforms/Xiaomi/alioth"
KONA_DBG2="$MU_ROOT/Silicium-ACPI/SoCs/Qualcomm/Kona/DBG2.aml"
FIXED_DBG2="$PROJECT_ROOT/Alioth-Engineering/acpi/Kona-DBG2-oemfix.aml"
for f in "$ACPI_INC" "$ALIOTH_ACPI/DSDT.asl" "$KONA_DBG2" "$FIXED_DBG2" "$MU_ROOT/build_uefi.sh"; do
    [ -f "$f" ] || { log "找不到 $f"; exit 1; }
done
command -v iasl >/dev/null 2>&1 || { log "缺少 iasl（sudo apt-get install acpica-tools）"; exit 1; }
log "phase17h 构建开始，日志：$BUILD_LOG"

# 0. 备份三个源文件，结束时无论成败都恢复
cp -f "$ACPI_INC" "$ACPI_INC.pre-phase17h-$STAMP.bak"
cp -f "$KONA_DBG2" "$KONA_DBG2.pre-phase17h-$STAMP.bak"
cp -f "$ALIOTH_ACPI/DSDT.asl" "$ALIOTH_ACPI/DSDT.asl.pre-phase17h-$STAMP.bak"
restore_sources() {
    cp -f "$ACPI_INC.pre-phase17h-$STAMP.bak" "$ACPI_INC"
    cp -f "$KONA_DBG2.pre-phase17h-$STAMP.bak" "$KONA_DBG2"
    cp -f "$ALIOTH_ACPI/DSDT.asl.pre-phase17h-$STAMP.bak" "$ALIOTH_ACPI/DSDT.asl"
    log "已恢复 ACPI.inc、Kona/DBG2.aml、DSDT.asl（备份后缀 .pre-phase17h-$STAMP.bak）"
}
trap restore_sources EXIT

# 1. DSDT：检查 17e-all 前提，只改 PEP0 _HID 与 PEPH
python3 - "$ALIOTH_ACPI/DSDT.asl" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8', errors='replace').read()
hid_old = len(re.findall(r'Name ?\(_HID, "QCOM2519"\)', t))
pre = {
    'PEP0 _HID 为 QCOM2519（1 处）': hid_old == 1,
    'PEPH 为 VEN_QCOM&DEV_2519（1 处）': t.count('VEN_QCOM&DEV_2519') == 1,
    '17e-all 桩为 27 个': t.count('// phase17e-stub') == 27,
    '尚无 QCOM0617': 'QCOM0617' not in t and 'DEV_0617' not in t,
    'SMMU 为 QCOM2509（2 处）': len(re.findall(r'Name ?\(_HID, "QCOM2509"\)', t)) == 2,
}
for k, v in pre.items():
    print(f'前提 {k}: {v}')
    if not v:
        raise SystemExit(f'DSDT 不是预期的 17e-all 状态：{k}')
t = re.sub(r'Name( ?)\(_HID, "QCOM2519"\)', r'Name\1(_HID, "QCOM0617")', t)
t = t.replace('VEN_QCOM&DEV_2519', 'VEN_QCOM&DEV_0617')
post = {
    'PEP0 _HID 为 QCOM0617': len(re.findall(r'Name ?\(_HID, "QCOM0617"\)', t)) == 1,
    'PEPH 为 DEV_0617': t.count('VEN_QCOM&DEV_0617') == 1,
    '无 QCOM2519/DEV_2519 残留': 'QCOM2519' not in t and 'DEV_2519' not in t,
}
for k, v in post.items():
    print(f'结果 {k}: {v}')
    if not v:
        raise SystemExit(f'修改校验失败：{k}')
open(p, 'w', encoding='utf-8').write(t)
PY
log "编译 DSDT.asl（iasl -f）"
( cd "$ALIOTH_ACPI" && iasl -f -ve -p DSDT DSDT.asl )
python3 - "$ALIOTH_ACPI/DSDT.aml" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
for n, want in [(b'QCOM0617', True), (b'VEN_QCOM&DEV_0617', True), (b'QCOM2519', False), (b'DEV_2519', False), (b'QCOM2509', True)]:
    ok = (n in d) == want
    print(f'AML {"包含" if want else "不含"} {n.decode()}: {ok}')
    if not ok:
        raise SystemExit('AML 校验失败')
PY

# 2. DBG2：强制打包 + 换上修复表
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
open(p, 'w', encoding='utf-8').write(t)
PY
echo "$FIXED_DBG2_SHA256  $FIXED_DBG2" | sha256sum -c -
cp -f "$FIXED_DBG2" "$KONA_DBG2"
log "已换上修复后的 Kona DBG2"

# 3. 构建
export CLANG_BIN="$PROJECT_ROOT/tools/linux-bin/"
export PATH="$PROJECT_ROOT/tools/linux-bin:$PATH"
( cd "$MU_ROOT" && bash ./build_uefi.sh -d alioth -m 1 -i -c )
BUILT="$MU_ROOT/Mu-alioth-1.img"
[ -f "$BUILT" ] || { log "找不到构建产物 $BUILT"; exit 1; }

# 4. 确认 FV 中含修复后的 DBG2 和新的 DSDT
python3 - "$MU_ROOT/Build/aliothPkg" "$FIXED_DBG2" "$ALIOTH_ACPI/DSDT.aml" <<'PY'
import sys, pathlib
dbg2 = pathlib.Path(sys.argv[2]).read_bytes()
dsdt = pathlib.Path(sys.argv[3]).read_bytes()
fvs = [f for f in pathlib.Path(sys.argv[1]).rglob('*.Fv') if f.stat().st_size < 64 * 1024 * 1024]
ok_dbg2 = [str(f) for f in fvs if dbg2 in f.read_bytes()]
ok_dsdt = [str(f) for f in fvs if dsdt in f.read_bytes()]
print('含修复 DBG2 的 FV：', ok_dbg2)
print('含 phase17h DSDT 的 FV：', ok_dsdt)
if not ok_dbg2 or not ok_dsdt:
    raise SystemExit('FV 校验失败，镜像不可用')
PY

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase17h-pep8280-dbg2-$STAMP.img"
cp -f "$BUILT" "$DEST"
log "镜像：$DEST"
sha256sum "$DEST"
log "手机端：先离线注入 qcpep8280（tools/Apply-Phase17hQcpep8280Inject-Admin.ps1），电脑端启动 kd 监听，再 fastboot boot（不要 flash）。"
