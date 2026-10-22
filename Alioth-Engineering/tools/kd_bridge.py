# 用法：python kd_bridge.py <kd.exe> <工作目录> [额外 kd 参数...]
# Phase17g：后台运行 kd.exe（KDNET USB EEM），输出实时写入 <工作目录>\kd.log；
# 往 <工作目录>\inbox.txt 追加一行即发送一条 kd 命令；"!!BREAK" 一行表示发送 Ctrl+Break 让目标中断；"!!QUIT" 结束桥接。
# 注意：kd.exe 不能直接从 WindowsApps 启动（拒绝访问），要先把 WinDbg 包里的 amd64 目录复制出来。
import os, subprocess, sys, threading, time

kd, work = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
os.makedirs(work, exist_ok=True)
log_path = os.path.join(work, 'kd.log')
inbox = os.path.join(work, 'inbox.txt')
open(inbox, 'a').close()

# kd 运行在自己的（隐藏）控制台里；后台进程没有控制台，Ctrl+Break 只能先挂到 kd 的控制台上再发送
si = subprocess.STARTUPINFO()
si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
si.wShowWindow = 0
args = [kd, '-k', 'net:port=50005,key=1.2.3.4'] + extra
proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=si, bufsize=0)
# 桥接自己挂到 kd 控制台上发 Ctrl+Break 会把自己也中断（实测退出码 130），所以每次另起一个一次性的小进程去发送
BREAK_HELPER = r'''
import ctypes, sys
k = ctypes.WinDLL("kernel32", use_last_error=True)
k.FreeConsole()
if not k.AttachConsole(int(sys.argv[1])):
    sys.exit(10)
k.GenerateConsoleCtrlEvent(1, 0)
'''

def send_break():
    r = subprocess.run([sys.executable, '-c', BREAK_HELPER, str(proc.pid)],
                       creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    return 'Ctrl+Break 辅助进程返回码 %s（10 表示挂接控制台失败）' % r.returncode
log = open(log_path, 'ab', buffering=0)
log.write(('\n==== kd_bridge 启动 %s：%s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), ' '.join(args))).encode('utf-8'))

def pump():
    while True:
        b = proc.stdout.read1(65536) if hasattr(proc.stdout, 'read1') else proc.stdout.read(1)
        if not b:
            break
        log.write(b)
threading.Thread(target=pump, daemon=True).start()

pos = os.path.getsize(inbox)
while proc.poll() is None:
    size = os.path.getsize(inbox)
    if size > pos:
        with open(inbox, 'rb') as f:
            f.seek(pos)
            data = f.read()
        pos = size
        for raw in data.splitlines():
            line = raw.decode('utf-8', 'replace').strip()
            if not line:
                continue
            log.write(('\n>>> %s %s\n' % (time.strftime('%H:%M:%S'), line)).encode('utf-8'))
            if line == '!!BREAK':
                log.write(('[桥接] %s\n' % send_break()).encode('utf-8'))
            elif line == '!!QUIT':
                proc.stdin.write(b'qd\n')
                time.sleep(2)
                proc.kill()
            else:
                proc.stdin.write(line.encode('utf-8') + b'\n')
                proc.stdin.flush()
    time.sleep(0.3)
log.write(('\n==== kd 已退出，返回码 %s\n' % proc.returncode).encode('utf-8'))
