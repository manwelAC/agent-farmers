"""Single entry point: own the core and desktop lifetimes; no fixed ports."""
import asyncio
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

ROOT=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))
BASE=Path(sys.executable).parent if getattr(sys,'frozen',False) else ROOT

def launch():
    if '--core' in sys.argv:
        from core.server import serve
        index=sys.argv.index('--core');asyncio.run(serve(sys.argv[index+1],sys.argv[index+2]));return
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--headless-smoke',action='store_true');parser.add_argument('--data-dir');parser.add_argument('--screenshot');parser.add_argument('--view');parser.add_argument('--window-size');args=parser.parse_args()
    data=Path(args.data_dir or (Path(os.environ.get('LOCALAPPDATA',str(BASE)))/'AgentFarmers' if getattr(sys,'frozen',False) else BASE/'data')).resolve();data.mkdir(parents=True,exist_ok=True)
    # Cross-process lock: normal OS close/crash releases it automatically.
    lock=(data/'launch.lock').open('a+b')
    if lock.seek(0,os.SEEK_END)==0:lock.write(b'0');lock.flush()
    lock.seek(0)
    if os.name=='nt':
        import msvcrt
        try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:raise RuntimeError('Agent Farmers is already open for this data folder.')
    session=data/'session.json';session.unlink(missing_ok=True)
    godot=next(iter((BASE/'.tools/godot').glob('*win64.exe')),None) if (BASE/'.tools/godot').exists() else BASE/'godot.exe'
    if not godot or not godot.is_file():raise RuntimeError('Godot runtime is missing. See the setup instructions.')
    core_args=[sys.executable,'--core',str(data),str(session)] if getattr(sys,'frozen',False) else [sys.executable,str(ROOT/'launch.py'),'--core',str(data),str(session)]
    log=(data/'runtime.log').open('a',encoding='utf-8')
    core=subprocess.Popen(core_args,cwd=BASE,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    ui=None;connection=None
    try:
        for _ in range(200):
            if core.poll() is not None:raise RuntimeError('The local core stopped. See '+str(data/'runtime.log'))
            if session.exists():connection=json.loads(session.read_text());break
            time.sleep(.05)
        if connection is None:raise RuntimeError('The core did not become ready.')
        command=[str(godot),'--path',str(BASE/'desktop'),'--rendering-method','gl_compatibility']
        if args.window_size:
            import re
            if not re.fullmatch(r'[1-9][0-9]{2,3}x[1-9][0-9]{2,3}',args.window_size):raise ValueError('Window size must be WIDTHxHEIGHT.')
            command+=['--resolution',args.window_size]
        if args.headless_smoke:command+=['--headless']
        command+=['--','--session',str(session)]
        if args.headless_smoke:command+=['--smoke']
        if args.screenshot:command+=['--screenshot',str(Path(args.screenshot).resolve())]
        if args.view:command+=['--view',args.view]
        if args.window_size:command+=['--window-size',args.window_size]
        ui=subprocess.Popen(command,cwd=BASE,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0);code=ui.wait()
        if code:raise RuntimeError('The desktop stopped unexpectedly. See '+str(data/'runtime.log'))
    finally:
        if connection:
            try:
                request=urllib.request.Request('http://127.0.0.1:'+str(connection['port'])+'/v1/command',data=b'{"action":"shutdown"}',headers={'Authorization':'Bearer '+connection['token'],'Content-Type':'application/json'})
                urllib.request.urlopen(request,timeout=5).close()
            except OSError:pass
        try:core.wait(timeout=15)
        except subprocess.TimeoutExpired:core.terminate();core.wait(timeout=5)
        log.close();lock.close()

if __name__=='__main__':
    try:launch()
    except Exception as error:
        if '--headless-smoke' not in sys.argv and os.name=='nt':ctypes.windll.user32.MessageBoxW(0,str(error),'Agent Farmers',0x10)
        else:print(str(error),file=sys.stderr)
        sys.exit(1)
