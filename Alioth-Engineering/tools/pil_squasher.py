# SPDX-License-Identifier: BSD-3-Clause
# Python 移植自 linux-msm/pil-squasher (pil-squasher.c, commit 3c9f8b8, Copyright (c) 2019 Linaro Ltd.)
# 作用：把高通分段固件 <name>.mdt + <name>.bXX 合并成单个 <name>.mbn（Windows qcsubsys/PIL 加载用）。
#
# 与原版 C 实现的差异：
#   - 段文件 .bXX 缺失或长度不足时直接报错退出（原版只 warn，并把未初始化内存写入输出）。
#   - 结束时打印各段信息，便于核对。
#
# 用法：python -I pil_squasher.py <输出.mbn> <输入.mdt>

import struct
import sys
from pathlib import Path

ELFMAG = b"\x7fELF"
ELFCLASS32 = 1
ELFCLASS64 = 2


def fail(msg):
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def pread(f, size, offset):
    f.seek(offset)
    return f.read(size)


def pwrite(f, data, offset):
    f.seek(offset)
    f.write(data)


def main():
    if len(sys.argv) != 3:
        fail("用法: pil_squasher.py <输出.mbn> <输入.mdt>")

    mbn_path = Path(sys.argv[1])
    mdt_path = Path(sys.argv[2])
    if mdt_path.suffix.lower() != ".mdt":
        fail(f"{mdt_path} 不是 .mdt 文件")

    with open(mdt_path, "rb") as mdt, open(mbn_path, "wb") as mbn:
        e_ident = pread(mdt, 16, 0)
        if e_ident[:4] != ELFMAG:
            fail(f"{mdt_path} 不是 ELF 文件")

        ei_class = e_ident[4]
        endian = "<" if e_ident[5] == 1 else ">"
        if ei_class == ELFCLASS32:
            ehdr_size, phdr_size = 52, 32
            ehdr = pread(mdt, ehdr_size, 0)
            phoff = struct.unpack_from(endian + "I", ehdr, 28)[0]
            phnum = struct.unpack_from(endian + "H", ehdr, 44)[0]

            def parse_phdr(b):
                # p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align
                t, off, _va, _pa, filesz, _memsz, flags, _al = struct.unpack(endian + "8I", b)
                return t, off, filesz, flags
        elif ei_class == ELFCLASS64:
            ehdr_size, phdr_size = 64, 56
            ehdr = pread(mdt, ehdr_size, 0)
            phoff = struct.unpack_from(endian + "Q", ehdr, 32)[0]
            phnum = struct.unpack_from(endian + "H", ehdr, 56)[0]

            def parse_phdr(b):
                # p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align
                t, flags, off, _va, _pa, filesz, _memsz, _al = struct.unpack(endian + "2I6Q", b)
                return t, off, filesz, flags
        else:
            fail(f"不支持的 ELF class {ei_class}")

        pwrite(mbn, ehdr, 0)

        # 第 0 个程序头描述 ELF 头+程序头表本身；hash 段紧跟其后存放在 mdt 中
        _t0, _o0, hashoffset, _f0 = parse_phdr(pread(mdt, phdr_size, phoff))

        print(f"输入: {mdt_path}  ELF{'32' if ei_class == ELFCLASS32 else '64'}  段数: {phnum}")
        for i in range(phnum):
            offset = phoff + i * phdr_size
            raw = pread(mdt, phdr_size, offset)
            pwrite(mbn, raw, offset)
            p_type, p_offset, p_filesz, p_flags = parse_phdr(raw)

            if not p_filesz:
                print(f"  段 {i:2d}: type=0x{p_type:x} filesz=0 跳过")
                continue

            segment = b""
            source = ""
            if ((p_flags >> 24) & 7) == 2:
                segment = pread(mdt, p_filesz, hashoffset)
                hashoffset += p_filesz
                if segment and len(segment) != p_filesz:
                    fail(f"段 {i} (hash) 从 mdt 读取不完整: {len(segment)}/{p_filesz}")
                source = "mdt(hash)"

            if not segment:
                bxx = mdt_path.with_suffix(f".b{i:02d}")
                if not bxx.exists():
                    fail(f"缺少段文件 {bxx}")
                segment = bxx.read_bytes()[:p_filesz]
                if len(segment) != p_filesz:
                    fail(f"段文件 {bxx} 长度不足: {len(segment)}/{p_filesz}")
                source = bxx.name

            pwrite(mbn, segment, p_offset)
            print(f"  段 {i:2d}: type=0x{p_type:x} offset=0x{p_offset:x} filesz=0x{p_filesz:x} 来源={source}")

    print(f"输出: {mbn_path}  大小: {mbn_path.stat().st_size} 字节")


if __name__ == "__main__":
    main()
