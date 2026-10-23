#!/bin/sh
# 编译 + 测试签名 + 生成 cat，输出驱动包到 pkg/
# 用法（Git Bash）：MSYS2_ARG_CONV_EXCL='*' /c/yjc_code/K40_Win11/Alioth-Engineering/drivers/pep0_stub/build-pkg.sh
set -e
cd "$(dirname "$0")"
K="C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0"
THUMB=7151DDBEB8836BE0D0733A53B1B5700C787E1FF7   # CN=K40 Alioth Test Driver Signing（当前用户证书库）
../kmdf_hello/build.sh pep0stub.c pep0stub 15
rm -rf pkg && mkdir pkg
cp pep0stub.sys pep0stub.inf pkg/
"$K/x64/signtool.exe" sign /fd sha256 /sha1 $THUMB /s My pkg/pep0stub.sys
PKGWIN=$(cygpath -w "$PWD/pkg")
"$K/x86/Inf2Cat.exe" /driver:"$PKGWIN" /os:10_CO_ARM64
"$K/x64/signtool.exe" sign /fd sha256 /sha1 $THUMB /s My pkg/pep0stub.cat
sha256sum pkg/*
echo "驱动包已生成：$PKGWIN"
