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

BUILD_LOG="$LOG_DIR/mu-alioth-phase12-build-$(date +%Y%m%d-%H%M%S).log"
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

log "Applying phase12 ACPI patch: keep Phase11 DSP-root enumeration and add qcsubsys metadata _DSD"
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

def find_device_block(source: str, device_name: str):
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
    return start, end, source[start:end]

def replace_top_level_dep(source: str, device_name: str, providers: list[str]) -> str:
    start, end, block = find_device_block(source, device_name)
    hid_pos = block.find("Name(_HID")
    if hid_pos < 0:
        hid_pos = block.find("Name (_HID")
    if hid_pos < 0:
        raise SystemExit(f"Cannot locate _HID in Device({device_name})")

    dep_pos = block.find("Name(_DEP", 0, hid_pos)
    dep_len = len("Name(_DEP")
    if dep_pos < 0:
        dep_pos = block.find("Name (_DEP", 0, hid_pos)
        dep_len = len("Name (_DEP")
    if dep_pos < 0:
        raise SystemExit(f"Cannot locate top-level _DEP before _HID in Device({device_name})")

    open_brace = block.find("{", dep_pos)
    if open_brace < 0 or open_brace > hid_pos:
        raise SystemExit(f"Cannot locate _DEP package opening brace in Device({device_name})")

    depth = 0
    dep_end = None
    for i in range(open_brace, len(block)):
        ch = block[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                dep_end = i + 1
                break
    if dep_end is None:
        raise SystemExit(f"Cannot locate _DEP package end in Device({device_name})")
    while dep_end < len(block) and block[dep_end].isspace():
        dep_end += 1
    if dep_end < len(block) and block[dep_end] == ")":
        dep_end += 1
    else:
        raise SystemExit(f"Cannot locate _DEP Name closing parenthesis in Device({device_name})")

    dep_method = "Name(_DEP, Package(0x%x)\n            {\n" % len(providers)
    dep_method += ",\n".join(f"                {provider}" for provider in providers)
    dep_method += "\n            })"
    new_block = block[:dep_pos] + dep_method + block[dep_end:]
    return source[:start] + new_block + source[end:]

def asl_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

def asl_value(value):
    if isinstance(value, int):
        if value == 0:
            return "Zero"
        if value == 1:
            return "One"
        return f"0x{value:x}"
    if isinstance(value, str):
        return asl_string(value)
    if isinstance(value, list):
        if len(value) == 1:
            header = "Package(One)"
        else:
            header = f"Package(0x{len(value):x})"
        body = ",\n".join("                                " + asl_value(item) for item in value)
        return f"{header}\n                            {{\n{body}\n                            }}"
    raise TypeError(f"Unsupported ASL value: {value!r}")

def make_dsd(properties: list[tuple[str, object]]) -> str:
    lines = [
        "Name(_DSD, Package(0x2)",
        "            {",
        "                Buffer(0x10)",
        "                {",
        "                    0x14, 0xd8, 0xff, 0xda, 0xba, 0x6e, 0x8c, 0x4d,",
        "                    0x8a, 0x91, 0xbc, 0x9b, 0xbf, 0x4a, 0xa3, 0x01",
        "                },",
        f"                Package(0x{len(properties):x})",
        "                {",
    ]
    for idx, (name, value) in enumerate(properties):
        suffix = "," if idx < len(properties) - 1 else ""
        lines.extend([
            "                    Package(0x2)",
            "                    {",
            f"                        {asl_string(name)},",
            f"                        {asl_value(value)}",
            f"                    }}{suffix}",
        ])
    lines.extend([
        "                }",
        "            })",
    ])
    return "\n".join(lines)

def add_device_dsd(source: str, device_name: str, properties: list[tuple[str, object]]) -> str:
    start, end, block = find_device_block(source, device_name)
    if "Name(_DSD" in block or "Name (_DSD" in block:
        return source

    dsd = make_dsd(properties)
    insert_pos = block.find("\n            Method(_CRS")
    if insert_pos < 0:
        insert_pos = block.find("\n            Method (_CRS")
    if insert_pos < 0:
        insert_pos = block.find("\n            Method(_STA")
        if insert_pos < 0:
            raise SystemExit(f"Cannot locate insertion point for _DSD in Device({device_name})")
        sta_open = block.find("{", insert_pos)
        depth = 0
        sta_end = None
        for i in range(sta_open, len(block)):
            ch = block[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    sta_end = i + 1
                    break
        if sta_end is None:
            raise SystemExit(f"Cannot locate _STA end in Device({device_name})")
        insert_pos = sta_end

    new_block = block[:insert_pos] + "\n            " + dsd + block[insert_pos:]
    return source[:start] + new_block + source[end:]

for device in ["ADSP", "CDSP", "SPSS", "SCSS"]:
    text = replace_device_sub(text, device, "MTP08280")

# Phase12 is intentionally narrow: match the dependency shape of SPSS, which is
# the only Phase10 DSP root that reached Windows PnP. If ADSP/CDSP/SCSS appear
# after this, the previous blocker is in ARPC/SSDD/GLNK/IPC0 dependency gating.
phase12_providers = [r"\_SB_.PEP0", r"\_SB_.PILC", r"\_SB_.RPEN"]
for device in ["ADSP", "CDSP", "SCSS"]:
    text = replace_top_level_dep(text, device, phase12_providers)

pil_tz = "{E2EB84C1-4068-4994-A48F-F3AC0D38DC29}"
fastrpc = "{E022FF1A-C06C-42D8-94FE-90D876FC0B75}"
glink = "{F9D15453-8335-434c-AA72-FCD925F135F3}"
audio_pd = "{0A35A787-A69F-4A90-8B78-0710BA7BB82C}"

metadata = {
    "ADSP": [
        ("SubsystemName", "ADSP"),
        ("RPEC", ["{99CA9C16-4E1E-4970-B49E-2CA56753588B}"]),
        ("Interfaces", [pil_tz, fastrpc, glink]),
        ("PDInfo.NumPDs", 1),
        ("PDInfo.0.PDName", "msm/adsp/audio_pd"),
        ("PDInfo.0.GUID", audio_pd),
    ],
    "CDSP": [
        ("SubsystemName", "CDSP"),
        ("RPEC", ["{DDAE0B76-6595-4469-A254-AD116DC4012A}"]),
        ("Interfaces", [pil_tz, fastrpc, glink]),
    ],
    "SCSS": [
        ("SubsystemName", "SCSS"),
        ("RPEC", ["{2c17a886-fe66-4e10-a6ec-9e9ea942eb24}"]),
        ("Interfaces", [pil_tz, fastrpc, glink]),
    ],
    "SPSS": [
        ("SubsystemName", "SPSS"),
        ("RPEC", ["{3692ce30-33e7-4b69-9f09-83efe52e107d}"]),
        ("Interfaces", [pil_tz]),
    ],
}

for device, properties in metadata.items():
    text = add_device_dsd(text, device, properties)

pilc_scope = "Scope(\\_SB_.PILC)"
if pilc_scope not in text:
    text += '\n        Scope(\\_SB_.PILC)\n        {\n            Method(_SUB, 0x0, NotSerialized)\n            {\n                Return("MTP08280")\n            }\n        }\n'
elif "MTP08280" not in text[text.find(pilc_scope):text.find(pilc_scope) + 300]:
    raise SystemExit("PILC _SUB scope exists but does not contain MTP08280; inspect manually")

if text != original:
    backup = asl.with_name(f"DSDT.asl.pre-phase12-{stamp}.bak")
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
    "phase12_adsp_dep": r"Device(ADSP)" in text and r"\_SB_.ARPC" not in find_device_block(text, "ADSP")[2].split('Name(_HID', 1)[0],
    "phase12_cdsp_dep": r"Device(CDSP)" in text and r"\_SB_.ARPC" not in find_device_block(text, "CDSP")[2].split('Name(_HID', 1)[0],
    "phase12_scss_dep": r"Device(SCSS)" in text and r"\_SB_.ARPC" not in find_device_block(text, "SCSS")[2].split('Name(_HID', 1)[0],
    "phase12_adsp_dsd": "PDInfo.0.PDName" in find_device_block(text, "ADSP")[2],
    "phase12_cdsp_dsd": "{DDAE0B76-6595-4469-A254-AD116DC4012A}" in find_device_block(text, "CDSP")[2],
    "phase12_scss_dsd": "{2c17a886-fe66-4e10-a6ec-9e9ea942eb24}" in find_device_block(text, "SCSS")[2],
    "phase12_spss_dsd": "{3692ce30-33e7-4b69-9f09-83efe52e107d}" in find_device_block(text, "SPSS")[2],
    "QCOM051D_absent": "QCOM051D" not in text,
    "QCOM0523_absent": "QCOM0523" not in text,
    "QCOM0599_absent": "QCOM0599" not in text,
    "QCOM0521_absent": "QCOM0521" not in text,
}
for key, value in checks.items():
    print(f"{key}: {value}")
    if not value:
        raise SystemExit(f"phase12 ASL verification failed: {key}")
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
    b"PDInfo.0.PDName", b"msm/adsp/audio_pd",
    b"{99CA9C16-4E1E-4970-B49E-2CA56753588B}",
    b"{DDAE0B76-6595-4469-A254-AD116DC4012A}",
    b"{2c17a886-fe66-4e10-a6ec-9e9ea942eb24}",
    b"{3692ce30-33e7-4b69-9f09-83efe52e107d}",
    b"{E2EB84C1-4068-4994-A48F-F3AC0D38DC29}",
    b"{E022FF1A-C06C-42D8-94FE-90D876FC0B75}",
    b"{F9D15453-8335-434c-AA72-FCD925F135F3}",
]
expected_absent = [b"QCOM051D", b"QCOM0523", b"QCOM0599", b"QCOM0521"]
for needle in expected_present:
    present = needle in data
    print(f"AML contains {needle.decode()}: {present}")
    if not present:
        raise SystemExit(f"phase12 AML verification failed, missing {needle.decode()}")
for needle in expected_absent:
    present = needle in data
    print(f"AML contains stale {needle.decode()}: {present}")
    if present:
        raise SystemExit(f"phase12 AML verification failed, stale {needle.decode()}")
print(f"AML MTP08280 count: {data.count(b'MTP08280')}")
for forbidden in [b"\\_SB_.ARPC"]:
    print(f"AML contains phase12 forbidden provider token {forbidden!r}: {forbidden in data}")
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

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase12-$(date +%Y%m%d-%H%M%S).img"
cp -f "$BUILT_IMAGE" "$DEST"

log "Copied patched UEFI image to: $DEST"
sha256sum "$DEST"
log "Validate with fastboot boot/flash, then run Trace-AliothAcpiPhase3State.ps1 and Trace-AliothAudioDependencyState.ps1."
