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

BUILD_LOG="$LOG_DIR/mu-alioth-phase8-build-$(date +%Y%m%d-%H%M%S).log"
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

link_tool clang clang clang-18
link_tool lld-link lld-link lld-link-18
link_tool llvm-lib llvm-lib llvm-lib-18
link_tool llvm-rc llvm-rc llvm-rc-18
link_tool llvm-objcopy llvm-objcopy llvm-objcopy-18

export CLANG_BIN="$TOOL_DIR/"
export PATH="$TOOL_DIR:$PATH"

cd "$MU_ROOT"

if [ "$SETUP_APT" = "1" ]; then
    log "Running setup_env.sh -p apt"
    bash ./setup_env.sh -p apt
fi

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

log "Applying phase8 ACPI HID patch to ASL and AML"
python3 - "$MU_ROOT" <<'PY'
from pathlib import Path
from datetime import datetime
import sys

root = Path(sys.argv[1])
alioth = root / "Silicium-ACPI" / "Platforms" / "Xiaomi" / "alioth"
asl = alioth / "DSDT.asl"
aml = alioth / "DSDT.aml"
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

if not asl.exists():
    raise SystemExit(f"DSDT.asl not found: {asl}")
if not aml.exists():
    raise SystemExit(f"DSDT.aml not found: {aml}")

hid_replacements = [
    # Phase8 pivots PILC from the 8250 qcpil8250 path to the Surface 8280 qcpil path.
    ("QCOM051B", "QCOM06E0"),
    ("QCOM251B", "QCOM06E0"),
    ("QCOM0533", "QCOM2533"),
    ("QCOM050B", "QCOM250B"),
    ("QCOM058D", "QCOM258D"),
    ("QCOM050E", "QCOM250E"),
    ("QCOM057C", "QCOM257C"),
    ("QCOM058B", "QCOM258B"),
    # Keep the verified Phase7 SSDD route.
    ("QCOM0522", "QCOM0620"),
    ("QCOM2522", "QCOM0620"),
]

text = asl.read_text(encoding="utf-8", errors="replace")
original_text = text
for old, new in hid_replacements:
    text = text.replace(f'Name(_HID, "{old}")', f'Name(_HID, "{new}")')
    text = text.replace(f'Name (_HID, "{old}")', f'Name (_HID, "{new}")')
if text != original_text:
    backup = asl.with_name(f"DSDT.asl.pre-phase8-{stamp}.bak")
    backup.write_text(original_text, encoding="utf-8")
    asl.write_text(text, encoding="utf-8")
    print(f"patched ASL, backup: {backup}")
else:
    print("ASL already patched or no matching _HID strings found")

data = aml.read_bytes()
original_data = data
for old, new in hid_replacements:
    data = data.replace(old.encode("ascii"), new.encode("ascii"))
if data != original_data:
    backup = aml.with_name(f"DSDT.aml.pre-phase8-{stamp}.bak")
    backup.write_bytes(original_data)
    aml.write_bytes(data)
    print(f"patched AML, backup: {backup}")
else:
    print("AML already patched or no matching HID strings found")

final = aml.read_bytes()
expected_present = [
    b"QCOM06E0",
    b"QCOM2533",
    b"QCOM250B",
    b"QCOM258D",
    b"QCOM250E",
    b"QCOM257C",
    b"QCOM258B",
    b"QCOM0620",
]
expected_absent = [
    b"QCOM051B",
    b"QCOM251B",
    b"QCOM0533",
    b"QCOM050B",
    b"QCOM058D",
    b"QCOM050E",
    b"QCOM057C",
    b"QCOM058B",
    b"QCOM0522",
    b"QCOM2522",
]
for needle in expected_present:
    present = needle in final
    print(f"AML contains {needle.decode()}: {present}")
    if not present:
        raise SystemExit(f"phase8 AML verification failed, missing {needle.decode()}")
for needle in expected_absent:
    present = needle in final
    print(f"AML contains {needle.decode()}: {present}")
    if present:
        raise SystemExit(f"phase8 AML verification failed, stale {needle.decode()}")
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

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase8-$(date +%Y%m%d-%H%M%S).img"
cp -f "$BUILT_IMAGE" "$DEST"

log "Copied patched UEFI image to: $DEST"
sha256sum "$DEST"
log "Use fastboot boot for first validation. Do not flash persistently until behavior is confirmed."
