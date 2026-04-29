#!/usr/bin/env bash
set -euo pipefail

DEST="/c/yjc_code/K40_Win11/sound_code/ref_repos"
mkdir -p "$DEST"
cd "$DEST"

clone_if_missing() {
  local repo="$1"
  local name="$2"
  if [ -d "$name/.git" ] || [ -d "$name" ]; then
    echo "SKIP $name"
  else
    git clone --depth=1 "$repo" "$name"
  fi
}

clone_if_missing "https://github.com/WOA-Project/windows_qcom_platforms" "windows_qcom_platforms"
clone_if_missing "https://github.com/WOA-Project/Qualcomm-Reference-Drivers" "Qualcomm-Reference-Drivers"
clone_if_missing "https://github.com/qaz6750/XiaoMi9-Drivers" "XiaoMi9-Drivers"
clone_if_missing "https://github.com/LineageOS/android_device_xiaomi_apollon" "android_device_xiaomi_apollon"
clone_if_missing "https://github.com/LineageOS/android_device_xiaomi_sm8250-common" "android_device_xiaomi_sm8250-common"
