"""Provider-owned tools. No tool capability is inferred from sign-in alone."""
import asyncio
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

LABELS={'codex':'Codex','antigravity':'Antigravity','claude':'Claude Code','opencode':'OpenCode'}
HIDDEN=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0

def redact(text):
    text=re.sub(r'\b(?:sk-[\w-]{12,}|gh[pousr]_[\w]{20,})\b','[credential redacted]',str(text))
    return re.sub(r'(?i)(Bearer\s+|(?:api_key|password|secret|access_token)\s*[:=]\s*)[^\s,;]+',r'\1[redacted]',text)

async def command(args,timeout=15):
    process=await asyncio.create_subprocess_exec(*args,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE,creationflags=HIDDEN)
    try:out,err=await asyncio.wait_for(process.communicate(),timeout)
    except (asyncio.TimeoutError,asyncio.CancelledError) as error:
        if process.returncode is None:process.kill()
        await process.communicate()
        if isinstance(error,asyncio.CancelledError):raise
        raise ValueError('Connection check timed out.')
    return process.returncode,out.decode('utf-8','replace'),err.decode('utf-8','replace')

def clean_environment():
    env=os.environ.copy()
    for key in ('CODEX_APP_TOOLS_PIPE_PATH','CODEX_SESSION_ID','CODEX_THREAD_ID','CODEX_TOOL_CALL_ID','CODEX_PERMISSION_PROFILE','CODEX_INTERNAL_ORIGINATOR_OVERRIDE','CODEX_TASK_WORKSPACE_VERIFYING_IDENTITY'):env.pop(key,None)
    return env

async def discover():
    found={}
    for key,name in LABELS.items():
        executable=shutil.which(('agy' if key=='antigravity' else key)+('.exe' if os.name=='nt' else ''))
        if not executable and key=='opencode':
            candidate=Path(os.environ.get('APPDATA',''))/'npm/node_modules/opencode-ai/bin/opencode.exe'
            if candidate.is_file():executable=str(candidate)
        if not executable and key=='claude':
            candidate=Path.home()/'.local/bin/claude.exe'
            if candidate.is_file():executable=str(candidate)
        if executable:found[key]={'id':key,'name':name,'command':[executable],'environment':'Windows' if os.name=='nt' else 'Native'}
    if 'antigravity' not in found and shutil.which('wsl.exe'):
        try:
            code,out,_=await command(['wsl.exe','--list','--quiet'],10)
            for distro in out.replace('\x00','').splitlines():
                distro=distro.strip()
                if not distro or 'docker' in distro.lower():continue
                code,path,_=await command(['wsl.exe','-d',distro,'-e','sh','-lc','command -v agy'],10)
                if code==0 and path.strip().startswith('/'):
                    found['antigravity']={'id':'antigravity','name':LABELS['antigravity'],'command':['wsl.exe','-d',distro,'-e',path.strip()],'environment':'WSL','distro':distro,'binary':path.strip()};break
        except (OSError,ValueError):pass
    return found

async def inspect(spec):
    result=dict(spec,installed=True,auth='Unknown',models=[],version='Unknown',capabilities={'files':'Unverified','web':'Unknown','images':'Unknown'},note='Tool access is task- and runtime-dependent.')
    try:
        _,out,_=await command(spec['command']+['--version'],10);result['version']=out.strip().splitlines()[0][:100] if out.strip() else 'Unknown'
        key=spec['id']
        if key in ('codex','claude'):
            code,_,_=await command(spec['command']+(['login','status'] if key=='codex' else ['auth','status']),10)
            result['auth']='Signed in' if code==0 else 'Sign in needed'
        if key=='antigravity':
            _,out,_=await command(spec['command']+['models'],20)
            result['models']=[line.split('\t')[0] for line in out.splitlines() if re.match(r'^[\w.-]+\t',line)];result['auth']='CLI available · sign-in unverified'
            result['capabilities']['web']='Unavailable through this adapter';result['note']='This CLI has no non-consuming account-status command. Verify connection sends a small no-tools request; model discovery alone does not prove sign-in.'
        if key=='opencode':
            _,out,_=await command(spec['command']+['models'],20)
            result['models']=[line.strip() for line in out.splitlines() if re.fullmatch(r'[\w.-]+/[\w./:-]+',line.strip())]
        if key=='codex':result['models']=await codex_models(spec)
        if key=='claude':result['capabilities']['web']='Unavailable through this adapter'
    except (OSError,ValueError,IndexError) as error:result['note']='Check incomplete: '+str(error)
    return result

async def verify(spec,folder):
    """Explicit user-requested account check. Never triggered by refresh/login."""
    args,env=build(spec,{'model':''},folder,False,False)
    prompt='Connection check only. Do not use tools, inspect files, or modify anything. Reply exactly AGENT_FARMERS_READY.'
    stdin=None
    if spec['id'] in ('codex','claude'):stdin=prompt.encode()
    elif spec['id']=='antigravity':
        args+=['-p',prompt]
        if '--print-timeout' in args:args[args.index('--print-timeout')+1]='45s'
    else:args+=[prompt]
    process=await asyncio.create_subprocess_exec(*args,cwd=folder,env=env,stdin=asyncio.subprocess.PIPE if stdin else asyncio.subprocess.DEVNULL,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE,creationflags=HIDDEN)
    try:
        out,err=await asyncio.wait_for(process.communicate(stdin),60)
        final='';failure=''
        for line in out.decode('utf-8','replace').splitlines():
            try:event=json.loads(line)
            except ValueError:continue
            if isinstance(event,dict):
                value=normalize(spec['id'],event);final=value['final'] or final;failure=value['error'] or failure
        if process.returncode!=0 or failure or final.strip()!='AGENT_FARMERS_READY':
            raise ValueError('The runtime did not confirm a usable session. Complete sign-in and retry. '+redact(failure or err.decode('utf-8','replace'))[:500])
    finally:
        if process.returncode is None:
            process.kill();await process.communicate()

async def codex_models(spec):
    p=await asyncio.create_subprocess_exec(*spec['command'],'app-server','--stdio',stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL,env=clean_environment(),creationflags=HIDDEN)
    async def read():
        p.stdin.write((json.dumps({'id':0,'method':'initialize','params':{'clientInfo':{'name':'agent_farmers','version':'0.1.0'}}})+'\n').encode());await p.stdin.drain()
        while line:=await p.stdout.readline():
            try:event=json.loads(line)
            except ValueError:continue
            if event.get('id')==0:
                p.stdin.write((json.dumps({'method':'initialized'})+'\n'+json.dumps({'id':1,'method':'model/list','params':{'limit':100}})+'\n').encode());await p.stdin.drain()
            if event.get('id')==1:return [m['model'] for m in event.get('result',{}).get('data',[]) if m.get('model')]
        return []
    try:return await asyncio.wait_for(read(),15)
    finally:
        if p.returncode is None:p.kill()
        await p.communicate()

def build(spec,worker,folder,write,web=False):
    key=spec['id'];model=worker.get('model','');env=clean_environment()
    if web and key!='codex':raise ValueError('Web access is not implemented for this adapter. Choose a capable connection or supply source files.')
    if key=='codex':
        args=['exec','--ignore-user-config','--ephemeral','--skip-git-repo-check','-c','default_permissions='+json.dumps(':workspace' if write else ':read-only'),'-c','approval_policy="never"','-c','features.prefer_mxc=true','-c','web_search='+json.dumps('live' if web else 'disabled'),'--json','--cd',str(folder)]
        if model:args+=['--model',model]
        return spec['command']+args+['-'],env
    if key=='claude':
        args=['-p','--output-format','stream-json','--verbose','--permission-mode','acceptEdits' if write else 'plan','--tools','Read,Edit,Write,Glob,Grep' if write else 'Read,Glob,Grep']
    elif key=='opencode':
        args=['run','--format','json','--dir',str(folder)]
        env['OPENCODE_PERMISSION']=json.dumps({'*':'deny','read':'allow','glob':'allow','grep':'allow','list':'allow','edit':'allow' if write else 'deny','external_directory':'deny'})
    else:
        settings={'toolPermission':'request-review','permissions':{'allow':['read_file(.)']+(['write_file(.)'] if write else []),'deny':['command(*)','execute_url(*)','mcp(*)','write_file(.git/)']+([] if write else ['write_file(*)']),'ask':[]}}
        args=['--output-format','stream-json','--sandbox','--mode','accept-edits' if write else 'plan','--print-timeout','15m','--settings',json.dumps(settings)]
    if model:args+=['--model',model]
    return spec['command']+args,env

def normalize(key,event):
    kind=event.get('type') or event.get('event');text='';final='';error='';usage=None
    if key=='codex':
        item=event.get('item',{})
        if kind=='item.completed' and item.get('type')=='agent_message':text=final=str(item.get('text',''))
        elif kind in ('item.started','item.completed') and item.get('type') in ('web_search','command_execution','file_change','mcp_tool_call'):
            text='Runtime tool event: '+item['type']+' · '+kind
        if kind=='turn.completed':usage=event.get('usage')
        if kind in ('error','turn.failed'):error=str(event.get('message') or event.get('error') or 'Runtime error')
    elif key=='antigravity' and kind=='result' and isinstance(event.get('result'),dict):
        result=event['result'];usage=result.get('usage')
        if result.get('status') in ('SUCCESS','success','completed'):text=final=str(result.get('response',''))
        else:error=str(result.get('error') or result.get('response') or 'Runtime error')
    elif key in ('antigravity','claude'):
        if kind=='result':
            if event.get('is_error'):error=str(event.get('result') or event.get('error'))
            else:text=final=str(event.get('result',''))
            usage=event.get('usage')
        if kind=='step_update':usage=event.get('step_update',{}).get('usage')
    elif key=='opencode':
        if kind=='text':text=final=str(event.get('part',{}).get('text',''))
        if kind=='step_finish':usage=event.get('part',{}).get('tokens')
        if kind=='error':error=str(event.get('error'))
    return dict(text=text,final=final,error=error,usage=usage)
