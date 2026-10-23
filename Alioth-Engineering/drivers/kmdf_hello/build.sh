#!/bin/sh
# 用 cl/link 直接编译 ARM64 KMDF 驱动（不依赖 WDK 的 VS 扩展）
# 用法：build.sh <源文件.c> <输出名> [KMDF 次版本号，默认 15]
set -e
SRC=$1; OUT=$2; KMIN=${3:-15}
VS="C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Tools/MSVC/14.50.35717"
K="C:/Program Files (x86)/Windows Kits/10"
V=10.0.26100.0
CL="$VS/bin/Hostx64/arm64/cl.exe"
LINK="$VS/bin/Hostx64/arm64/link.exe"
"$CL" -nologo -c -kernel -W4 -WX -O2 -Gy -GF -GS -Zi -Zp8 -utf-8 -wd4324 \
  -D_ARM64_ -DARM64 -D_WIN64 -DNTDDI_VERSION=0x0A00000C -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 \
  -DKMDF_VERSION_MAJOR=1 -DKMDF_VERSION_MINOR=$KMIN \
  -I"$K/Include/$V/km" -I"$K/Include/$V/km/crt" -I"$K/Include/$V/shared" -I"$K/Include/wdf/kmdf/1.$KMIN" \
  -Fo"$OUT.obj" -Fd"$OUT.vc.pdb" "$SRC"
"$LINK" -nologo -driver -subsystem:native,10.00 -machine:arm64 -entry:FxDriverEntry -nodefaultlib \
  -release -debug -pdb:"$OUT.pdb" -out:"$OUT.sys" "$OUT.obj" \
  -libpath:"$K/Lib/$V/km/arm64" -libpath:"$K/Lib/wdf/kmdf/arm64/1.$KMIN" \
  ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib WdfLdr.lib WdfDriverEntry.lib
echo "编译完成：$OUT.sys"
