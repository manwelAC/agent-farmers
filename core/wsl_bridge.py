"""Own a WSL child process group and relay cancellation and line events."""
import json
import os
import signal
import subprocess
import sys
import threading
import time

def main():
    message=json.loads(sys.stdin.readline())
    child=subprocess.Popen(sys.argv[1:]+['-p',message['prompt']],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    def forward(stream,stderr=False):
        for line in iter(stream.readline,b''):
            if stderr:line=(json.dumps({'type':'bridge_stderr','message':line.decode('utf-8','replace')})+'\n').encode()
            try:sys.stdout.buffer.write(line);sys.stdout.buffer.flush()
            except BrokenPipeError:break
    readers=[threading.Thread(target=forward,args=(stream,flag),daemon=True) for stream,flag in ((child.stdout,False),(child.stderr,True))]
    for reader in readers:reader.start()
    def cancel():
        for line in sys.stdin:
            try:value=json.loads(line)
            except ValueError:continue
            if value.get('cancel'):
                try:os.killpg(child.pid,signal.SIGTERM)
                except ProcessLookupError:return
                time.sleep(2)
                try:os.killpg(child.pid,signal.SIGKILL)
                except ProcessLookupError:pass
                return
    threading.Thread(target=cancel,daemon=True).start()
    code=child.wait()
    for reader in readers:reader.join(5)
    try:os.killpg(child.pid,signal.SIGTERM)
    except ProcessLookupError:pass
    return code
if __name__=='__main__':sys.exit(main())
