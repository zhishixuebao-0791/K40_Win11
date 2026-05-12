#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/home/ucchip/K40_Win11}"
MU_ROOT="${MU_ROOT:-$PROJECT_ROOT/sound_code/Mu-Silicium}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/UEFI-Images}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
SETUP_APT="${SETUP_APT:-0}"

LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
TOOL_DIR="$PROJECT_ROOT/tools/linux-bin"
mkdir -p "$LOG_DIR" "$TOOL_DIR" "$OUTPUT_DIR"

BUILD_LOG="$LOG_DIR/mu-alioth-phase10-build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$BUILD_LOG") 2>&1

log() {
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

link_tool() {
    local name="$1"
    shift
    local candidate=""
    for tool in "$@"; do
        if command -v "$tool" >/dev/null 2>&1; then
            candidate="$(command -v "$tool")"
            break
        fi
    done
    if [ -z "$candidate" ] && [ -x "$TOOL_DIR/$name" ]; then
        candidate="$(readlink -f "$TOOL_DIR/$name")"
    fi
    if [ -z "$candidate" ]; then
        log "Missing required tool for $name. Tried: $*"
        return 1
    fi
    ln -sfn "$candidate" "$TOOL_DIR/$name"
    log "Tool $name -> $candidate"
}

log "Build log: $BUILD_LOG"
log "Project root: $PROJECT_ROOT"
log "Mu root: $MU_ROOT"
log "Output dir: $OUTPUT_DIR"

if [ ! -f "$MU_ROOT/build_uefi.sh" ]; then
    log "Mu-Silicium build script not found: $MU_ROOT/build_uefi.sh"
    exit 1
fi

if [ "$SETUP_APT" = "1" ]; then
    log "Installing Ubuntu build dependencies including acpica-tools"
    sudo apt-get update
    sudo apt-get install -y acpica-tools clang lld llvm python3-pip
fi

link_tool clang clang clang-18
link_tool lld-link lld-link lld-link-18
link_tool llvm-lib llvm-lib llvm-lib-18
link_tool llvm-rc llvm-rc llvm-rc-18
link_tool llvm-objcopy llvm-objcopy llvm-objcopy-18

if ! command -v iasl >/dev/null 2>&1; then
    log "Missing iasl. Install it with: sudo apt-get install acpica-tools"
    exit 1
fi

export CLANG_BIN="$TOOL_DIR/"
export PATH="$TOOL_DIR:$PATH"

cd "$MU_ROOT"

log "Updating submodules"
git submodule update --init --recursive

log "Ensuring Python build dependencies"
if ! python3 - <<'PY' >/dev/null 2>&1
import edk2toolext
PY
then
    python3 -m pip install --user --break-system-packages -r pip-requirements.txt
fi

log "Normalizing migrated CRLF in build metadata"
find . -type f \( -name '*.sh' -o -name '*.conf' -o -name 'Makefile' -o -name '*.patch' \) -exec perl -pi -e 's/\r$//' {} +

log "Applying phase10 ACPI patch: keep PILC/SSDD stable, expose DSP roots as Surface 8280 HIDs"
python3 - "$MU_ROOT" <<'PY'
from pathlib import Path
from datetime import datetime
import re
import sys

root = Path(sys.argv[1])
alioth = root / "Silicium-ACPI" / "Platforms" / "Xiaomi" / "alioth"
asl = alioth / "DSDT.asl"
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

if not asl.exists():
    raise SystemExit(f"DSDT.asl not found: {asl}")

text = asl.read_text(encoding="utf-8", errors="replace")
original = text

hid_replacements = [
    ("QCOM051B", "QCOM06E0"),
    ("QCOM251B", "QCOM06E0"),
    ("QCOM0533", "QCOM2533"),
    ("QCOM050B", "QCOM250B"),
    ("QCOM058D", "QCOM258D"),
    ("QCOM050E", "QCOM250E"),
    ("QCOM057C", "QCOM257C"),
    ("QCOM058B", "QCOM258B"),
    ("QCOM0522", "QCOM0620"),
    ("QCOM2522", "QCOM0620"),
    ("QCOM051D", "QCOM061B"),
    ("QCOM0523", "QCOM06B0"),
    ("QCOM0599", "QCOM068D"),
    ("QCOM0521", "QCOM061F"),
]

for old, new in hid_replacements:
    text = text.replace(f'Name(_HID, "{old}")', f'Name(_HID, "{new}")')
    text = text.replace(f'Name (_HID, "{old}")', f'Name (_HID, "{new}")')

def replace_device_sub(source: str, device_name: str, sub_value: str) -> str:
    marker = f"Device({device_name})"
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"Cannot locate {marker}")
    open_brace = source.find("{", start)
    if open_brace < 0:
        raise SystemExit(f"Cannot locate opening brace for {marker}")
    depth = 0
    end = None
    for i in range(open_brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"Cannot locate end of {marker}")

    block = source[start:end]
    sub_method = (
        f'Method(_SUB, 0x0, NotSerialized)\n'
        f'            {{\n'
        f'                Return("{sub_value}")\n'
        f'            }}'
    )
    if re.search(r"Method\s*\(\s*_SUB\s*,", block):
        block = re.sub(
            r'Method\s*\(\s*_SUB\s*,\s*0x0,\s*NotSerialized\s*\)\s*\{\s*Return\s*\("[A-Z0-9_]+"\)\s*\}',
            sub_method,
            block,
            count=1,
            flags=re.S,
        )
    elif 'Alias(\\_SB_.PSUB, _SUB)' in block:
        block = block.replace('Alias(\\_SB_.PSUB, _SUB)', sub_method, 1)
    else:
        insert_at = block.find("\n", block.find("Name(_HID"))
        if insert_at < 0:
            raise SystemExit(f"Cannot insert _SUB for {marker}")
        block = block[:insert_at + 1] + "            " + sub_method + "\n" + block[insert_at + 1:]

    return source[:start] + block + source[end:]

for device in ["ADSP", "CDSP", "SPSS", "SCSS"]:
    text = replace_device_sub(text, device, "MTP08280")

pilc_scope = "Scope(\\_SB_.PILC)"
if pilc_scope not in text:
    text += '\n        Scope(\\_SB_.PILC)\n        {\n            Method(_SUB, 0x0, NotSerialized)\n            {\n                Return("MTP08280")\n            }\n        }\n'
elif "MTP08280" not in text[text.find(pilc_scope):text.find(pilc_scope) + 300]:
    raise SystemExit("PILC _SUB scope exists but does not contain MTP08280; inspect manually")

if text != original:
    backup = asl.with_name(f"DSDT.asl.pre-phase10-{stamp}.bak")
    backup.write_text(original, encoding="utf-8")
    asl.write_text(text, encoding="utf-8")
    print(f"patched ASL, backup: {backup}")
else:
    print("ASL unchanged")

checks = {
    "QCOM06E0": "QCOM06E0" in text,
    "QCOM0620": "QCOM0620" in text,
    "QCOM061B": "QCOM061B" in text,
    "QCOM06B0": "QCOM06B0" in text,
    "QCOM068D": "QCOM068D" in text,
    "QCOM061F": "QCOM061F" in text,
    "QCOM0520_kept": "QCOM0520" in text,
    "QCOM0532_kept": "QCOM0532" in text,
    "MTP08280": text.count("MTP08280") >= 5,
    "QCOM051D_absent": "QCOM051D" not in text,
    "QCOM0523_absent": "QCOM0523" not in text,
    "QCOM0599_absent": "QCOM0599" not in text,
    "QCOM0521_absent": "QCOM0521" not in text,
}
for key, value in checks.items():
    print(f"{key}: {value}")
    if not value:
        raise SystemExit(f"phase10 ASL verification failed: {key}")
PY

ALIOTH_ACPI="$MU_ROOT/Silicium-ACPI/Platforms/Xiaomi/alioth"
log "Compiling patched DSDT.asl to DSDT.aml with iasl -f"
(
    cd "$ALIOTH_ACPI"
    iasl -f -ve -p DSDT DSDT.asl
)

log "Verifying compiled DSDT.aml"
python3 - "$ALIOTH_ACPI/DSDT.aml" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
expected_present = [
    b"QCOM06E0", b"QCOM0620", b"QCOM061B", b"QCOM06B0",
    b"QCOM068D", b"QCOM061F", b"QCOM0520", b"QCOM0532", b"MTP08280",
]
expected_absent = [b"QCOM051D", b"QCOM0523", b"QCOM0599", b"QCOM0521"]
for needle in expected_present:
    present = needle in data
    print(f"AML contains {needle.decode()}: {present}")
    if not present:
        raise SystemExit(f"phase10 AML verification failed, missing {needle.decode()}")
for needle in expected_absent:
    present = needle in data
    print(f"AML contains stale {needle.decode()}: {present}")
    if present:
        raise SystemExit(f"phase10 AML verification failed, stale {needle.decode()}")
print(f"AML MTP08280 count: {data.count(b'MTP08280')}")
PY

build_args=(-d alioth -m 1 -i)
if [ "$CLEAN_BUILD" = "1" ]; then
    build_args+=(-c)
fi

log "Running build_uefi.sh ${build_args[*]}"
bash ./build_uefi.sh "${build_args[@]}"

BUILT_IMAGE="$MU_ROOT/Mu-alioth-1.img"
if [ ! -f "$BUILT_IMAGE" ]; then
    log "Expected build output not found: $BUILT_IMAGE"
    exit 1
fi

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase10-$(date +%Y%m%d-%H%M%S).img"
cp -f "$BUILT_IMAGE" "$DEST"

log "Copied patched UEFI image to: $DEST"
sha256sum "$DEST"
log "Validate with fastboot boot/flash, then run Trace-AliothAudioDependencyState.ps1."
