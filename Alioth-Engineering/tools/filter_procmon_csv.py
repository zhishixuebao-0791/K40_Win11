# 流式筛选 Procmon 导出的 CSV（可达数 GB），只保留与 qcsubsys / ADSP 相关的事件。
# 用法：python filter_procmon_csv.py <boot_all.csv> <输出目录> [adsp|smmu]
# 输出：
#   qcsubsys_events.csv  命中的原始事件（保持时间顺序）
#   summary.txt          按 (操作, 路径, 结果) 汇总的计数，以及所有非 SUCCESS 的事件
#   context_after_load.csv  （smmu 模式）qcsmmu8280.sys 加载后 System 进程的前 N 条事件，不论路径

import csv
import sys
from collections import Counter
from pathlib import Path

KEYWORDS_ADSP = [
    "qcom061b", "\\0036", "alioth\\adsp", "qcsubsys", "rads.bin", "qcadsp",
    "driverdata\\qualcomm", "subsys_adsp", "pdinfo", "\\services\\qcsubsys",
    "qcom06e0\\2&daba3ff&0\\device parameters\\subsystemload",
]

KEYWORDS_SMMU = [
    "qcsmmu", "\\0037", "dev_2509", "smmc.bin", "lkmdtel", "55beca03",
    "{4d36e97d-e325-11ce-bfc1-08002be10318}\\0037",
]
CONTEXT_TRIGGER = "qcsmmu8280.sys"
CONTEXT_EVENTS = 3000

csv.field_size_limit(1 << 30)


def main():
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    profile = sys.argv[3] if len(sys.argv) > 3 else "adsp"
    keywords = KEYWORDS_SMMU if profile == "smmu" else KEYWORDS_ADSP
    out_dir.mkdir(parents=True, exist_ok=True)
    ctx_left = 0
    ctx_file = open(out_dir / "context_after_load.csv", "w", encoding="utf-8-sig", newline="") if profile == "smmu" else None
    ctx_writer = csv.writer(ctx_file) if ctx_file else None
    hits = 0
    total = 0
    counter = Counter()
    failures = []
    with open(src, encoding="utf-8-sig", errors="replace", newline="") as f, \
         open(out_dir / "qcsubsys_events.csv", "w", encoding="utf-8-sig", newline="") as fo:
        reader = csv.reader(f)
        header = next(reader)
        col = {name: i for i, name in enumerate(header)}
        writer = csv.writer(fo)
        writer.writerow(header)
        if ctx_writer:
            ctx_writer.writerow(header)
        ip, io, ir, iproc = col.get("Path"), col.get("Operation"), col.get("Result"), col.get("Process Name")
        for row in reader:
            total += 1
            if ip is None or ip >= len(row):
                continue
            path = row[ip]
            low = path.lower()
            if ctx_writer:
                proc = row[iproc] if iproc is not None else ""
                if ctx_left == 0 and row[io] == "Load Image" and low.endswith(CONTEXT_TRIGGER):
                    ctx_left = CONTEXT_EVENTS
                if ctx_left > 0 and proc == "System":
                    ctx_writer.writerow(row)
                    ctx_left -= 1
            if not any(k in low for k in keywords):
                continue
            hits += 1
            writer.writerow(row)
            key = (row[iproc] if iproc is not None else "", row[io], path, row[ir])
            counter[key] += 1
            if row[ir] != "SUCCESS":
                failures.append(row)
    with open(out_dir / "summary.txt", "w", encoding="utf-8") as fs:
        fs.write(f"总事件数: {total}\n命中事件数: {hits}\n表头: {header}\n\n")
        fs.write("==== 按 (进程, 操作, 路径, 结果) 汇总 ====\n")
        for (proc, op, path, res), n in sorted(counter.items(), key=lambda x: x[0][2].lower()):
            fs.write(f"{n:6d}  {proc:<14} {op:<24} {res:<22} {path}\n")
        fs.write("\n==== 非 SUCCESS 事件（时间顺序）====\n")
        for row in failures:
            fs.write(" | ".join(row) + "\n")
    if ctx_file:
        ctx_file.close()
    print(f"总事件数 {total}，命中 {hits}，非 SUCCESS {len(failures)}")


if __name__ == "__main__":
    main()
