param(
    [string]$MuRoot,
    [string]$OutputDir,
    [switch]$Clean,
    [switch]$SetupApt
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

function Quote-Bash {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Convert-ToWslPath {
    param([string]$Path)

    $converted = (& wsl.exe wslpath -a "$Path").Trim()
    if (-not $converted) {
        throw "Failed to convert path to WSL path: $Path"
    }
    return $converted
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$isNativeLinux = [System.IO.Path]::DirectorySeparatorChar -eq "/"

if ([string]::IsNullOrWhiteSpace($MuRoot)) {
    $preferred = Join-Path (Join-Path $repoRoot "sound_code") "Mu-Silicium"
    if (Test-Path -LiteralPath $preferred) {
        $MuRoot = (Resolve-Path -LiteralPath $preferred).Path
    }
}

if ([string]::IsNullOrWhiteSpace($MuRoot)) {
    $candidate = Get-ChildItem -LiteralPath $repoRoot -Directory -Recurse -Filter "Mu-Silicium" -ErrorAction SilentlyContinue |
        Where-Object {
            $dsdtProbe = Join-Path (Join-Path (Join-Path (Join-Path $_.FullName "Silicium-ACPI") "Platforms") "Xiaomi") "alioth"
            Test-Path -LiteralPath (Join-Path $dsdtProbe "DSDT.asl")
        } |
        Select-Object -First 1
    if ($candidate) {
        $MuRoot = $candidate.FullName
    }
}

if (-not $MuRoot -or -not (Test-Path -LiteralPath $MuRoot)) {
    throw "Mu-Silicium root not found: $MuRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "UEFI-Images"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$logDir = Join-Path (Join-Path $repoRoot "Alioth-Engineering") "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if ($isNativeLinux) {
    $bashRepoRoot = $repoRoot
    $bashMuRoot = (Resolve-Path -LiteralPath $MuRoot).Path
    $bashOutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
} else {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw "wsl.exe was not found. Run this on Ubuntu directly, or install WSL first."
    }
    $bashRepoRoot = Convert-ToWslPath $repoRoot
    $bashMuRoot = Convert-ToWslPath $MuRoot
    $bashOutputDir = Convert-ToWslPath $OutputDir
}

$cleanValue = if ($Clean) { "1" } else { "0" }
$setupAptValue = if ($SetupApt) { "1" } else { "0" }

$bashTemplate = @'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=__PROJECT_ROOT__
MU_ROOT=__MU_ROOT__
OUTPUT_DIR=__OUTPUT_DIR__
CLEAN_BUILD=__CLEAN_BUILD__
SETUP_APT=__SETUP_APT__

LOG_DIR="$PROJECT_ROOT/Alioth-Engineering/logs"
TOOL_DIR="$PROJECT_ROOT/tools/linux-bin"
mkdir -p "$LOG_DIR" "$TOOL_DIR" "$OUTPUT_DIR"

BUILD_LOG="$LOG_DIR/mu-alioth-phase4a-build-$(date +%Y%m%d-%H%M%S).log"
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

log "Normalizing Mu_Basecore files touched by MuPatches"
python3 - "$MU_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
paths = []
for patch in (root / "Resources" / "MuPatches").glob("*.patch"):
    for line in patch.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("--- a/") or line.startswith("+++ b/"):
            rel = line[6:].strip()
            if rel != "/dev/null" and rel not in paths:
                paths.append(rel)

for rel in paths:
    target = root / "Mu_Basecore" / rel
    if not target.exists():
        print(f"missing patch target: {target}")
        continue
    data = target.read_bytes()
    new = data.replace(b"\r\n", b"\n")
    if new != data:
        target.write_bytes(new)
        print(f"normalized LF: {target}")
PY

log "Applying phase4a ACPI HID patch to ASL and AML"
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

replacements = [
    ("QCOM051B", "QCOM251B"),
    ("QCOM0533", "QCOM2533"),
    ("QCOM050B", "QCOM250B"),
    ("QCOM058D", "QCOM258D"),
]

text = asl.read_text(encoding="utf-8", errors="replace")
original_text = text
for old, new in replacements:
    text = text.replace(f'Name(_HID, "{old}")', f'Name(_HID, "{new}")')
if text != original_text:
    backup = asl.with_name(f"DSDT.asl.pre-phase4a-{stamp}.bak")
    backup.write_text(original_text, encoding="utf-8")
    asl.write_text(text, encoding="utf-8")
    print(f"patched ASL, backup: {backup}")
else:
    print("ASL already patched")

data = aml.read_bytes()
original_data = data
for old, new in replacements:
    data = data.replace(old.encode("ascii"), new.encode("ascii"))
if data != original_data:
    backup = aml.with_name(f"DSDT.aml.pre-phase4a-{stamp}.bak")
    backup.write_bytes(original_data)
    aml.write_bytes(data)
    print(f"patched AML, backup: {backup}")
else:
    print("AML already patched")

expected_present = [b"QCOM251B", b"QCOM2533", b"QCOM250B", b"QCOM258D"]
expected_absent = [b"QCOM051B", b"QCOM0533", b"QCOM050B", b"QCOM058D"]
final = aml.read_bytes()
for needle in expected_present:
    present = needle in final
    print(f"AML contains {needle.decode()}: {present}")
    if not present:
        raise SystemExit(f"phase4a AML verification failed, missing {needle.decode()}")
for needle in expected_absent:
    present = needle in final
    print(f"AML contains {needle.decode()}: {present}")
    if present:
        raise SystemExit(f"phase4a AML verification failed, stale {needle.decode()}")
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

DEST="$OUTPUT_DIR/Mu-alioth-1-acpi-hid-phase4a-$(date +%Y%m%d-%H%M%S).img"
cp -f "$BUILT_IMAGE" "$DEST"

log "Copied patched UEFI image to: $DEST"
sha256sum "$DEST"
log "Use fastboot boot for first validation. Do not flash persistently until behavior is confirmed."
'@

$bashScript = $bashTemplate
$bashScript = $bashScript.Replace("__PROJECT_ROOT__", (Quote-Bash $bashRepoRoot))
$bashScript = $bashScript.Replace("__MU_ROOT__", (Quote-Bash $bashMuRoot))
$bashScript = $bashScript.Replace("__OUTPUT_DIR__", (Quote-Bash $bashOutputDir))
$bashScript = $bashScript.Replace("__CLEAN_BUILD__", (Quote-Bash $cleanValue))
$bashScript = $bashScript.Replace("__SETUP_APT__", (Quote-Bash $setupAptValue))

$runScript = Join-Path $logDir ("build-acpi-hid-phase4a-run-{0}.sh" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($runScript, $bashScript, [System.Text.UTF8Encoding]::new($false))
Write-Log "Wrote runner: $runScript"

if ($isNativeLinux) {
    & bash $runScript
} else {
    $wslRunScript = Convert-ToWslPath $runScript
    & wsl.exe bash $wslRunScript
}

if ($LASTEXITCODE -ne 0) {
    throw "Phase4a UEFI build failed with exit code $LASTEXITCODE."
}

Write-Log "Phase4a UEFI build completed."
