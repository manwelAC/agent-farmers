import asyncio
import json
import os
from pathlib import Path
import secrets
import sys
from aiohttp import web
from .engine import Engine
from . import providers

async def serve(root,session):
    engine=Engine(root);token=secrets.token_urlsafe(32);stop=asyncio.Event()
    @web.middleware
    async def protect(request,handler):
        if request.headers.get('Origin'):return web.json_response({'error':'Browser origins are not allowed.'},status=403)
        if not secrets.compare_digest(request.headers.get('Authorization',''),'Bearer '+token):return web.json_response({'error':'Unauthorized'},status=401)
        try:return await handler(request)
        except (ValueError,KeyError,TypeError,OSError) as error:return web.json_response({'error':providers.redact(str(error))},status=400)
    app=web.Application(middlewares=[protect],client_max_size=300_000)
    async def state(request):return web.json_response(engine.snapshot())
    async def detail(request):return web.json_response(engine.detail(request.match_info['id']))
    async def preview(request):
        from .store import output_path
        import base64
        artifact=engine.store.get('artifacts',request.match_info['id'])
        if not artifact:raise ValueError('Artifact not found.')
        project=engine.detail(artifact['projectId'])['project'];path=output_path(project['folder'],artifact['relative'])
        if not path.is_file():raise ValueError('The artifact no longer exists.')
        if path.suffix.lower() in ('.md','.txt','.csv','.json','.log') and path.stat().st_size<=1_000_000:
            return web.json_response({'kind':'text','name':artifact['relative'],'text':path.read_text(encoding='utf-8',errors='replace')})
        if path.suffix.lower() in ('.png','.jpg','.jpeg','.webp') and path.stat().st_size<=8_000_000:
            return web.json_response({'kind':'image','name':artifact['relative'],'format':path.suffix.lower(),'base64':base64.b64encode(path.read_bytes()).decode()})
        raise ValueError('This file type/size has no built-in preview. Open it using an appropriate external application.')
    async def websocket(request):
        ws=web.WebSocketResponse(heartbeat=20,max_msg_size=4096);await ws.prepare(request)
        queue=asyncio.Queue(maxsize=64);engine.listeners.add(queue)
        async def sender():
            while not ws.closed:await ws.send_json(await queue.get())
        task=asyncio.create_task(sender())
        try:
            async for message in ws:pass
        finally:engine.listeners.discard(queue);task.cancel()
        return ws
    async def command(request):
        value=await request.json();action=value.get('action');data=value.get('payload',{});result={}
        if action=='refresh':asyncio.create_task(engine.refresh())
        elif action=='worker.save':result=engine.worker(data)
        elif action=='project.create':result=engine.project(data)
        elif action=='project.discuss':engine.discuss(data['id'],data.get('message',''),data.get('initial') is True)
        elif action=='plan.save':result=engine.plan(data['id'],data)
        elif action=='plan.approve':result=engine.approval(data['id'],data)
        elif action=='project.start':engine.start(data['id'],data['approvalId'])
        elif action=='stop':await engine.cancel()
        elif action=='memory.save':result={'path':engine.remember(data['id'])}
        elif action=='open.folder':
            from .store import workspace
            folder=workspace(engine.detail(data['id'])['project']['folder']);os.startfile(folder)
        elif action=='open.artifact':
            from .store import output_path
            artifact=engine.store.get('artifacts',data['id'])
            if not artifact:raise ValueError('Artifact not found.')
            p=engine.detail(artifact['projectId'])['project'];path=output_path(p['folder'],artifact['relative'])
            if path.suffix.lower() not in ('.md','.txt','.pdf','.png','.jpg','.jpeg','.webp','.gif','.csv','.docx','.xlsx'):raise ValueError('Executable/active outputs are not opened automatically. Use Open workspace to inspect them.')
            if not path.is_file():raise ValueError('The artifact no longer exists.')
            os.startfile(path)
        elif action=='connection.login':
            engine.login(data['id'])
        elif action=='connection.verify':engine.verify_connection(data['id'])
        elif action=='shutdown':stop.set()
        else:raise ValueError('Unknown action.')
        return web.json_response({'ok':True,'result':result})
    app.router.add_get('/v1/state',state);app.router.add_get('/v1/projects/{id}',detail);app.router.add_get('/v1/artifacts/{id}/preview',preview);app.router.add_get('/v1/events',websocket);app.router.add_post('/v1/command',command)
    runner=web.AppRunner(app);await runner.setup();site=web.TCPSite(runner,'127.0.0.1',0);await site.start()
    port=site._server.sockets[0].getsockname()[1]
    session=Path(session);session.parent.mkdir(parents=True,exist_ok=True)
    temp=session.with_suffix('.tmp');temp.write_text(json.dumps({'version':1,'port':port,'token':token,'pid':os.getpid()}),encoding='utf-8');os.chmod(temp,0o600);temp.replace(session)
    refresh=asyncio.create_task(engine.refresh())
    try:await stop.wait()
    finally:
        engine.closed=True;await engine.cancel()
        if engine.active and not engine.active.done():
            try:await asyncio.wait_for(engine.active,10)
            except (asyncio.TimeoutError,asyncio.CancelledError):engine.active.cancel()
        pending=list(engine.background)
        if refresh not in pending:pending.append(refresh)
        for task in pending:task.cancel()
        await asyncio.gather(*pending,return_exceptions=True)
        await runner.cleanup();engine.store.db.close();session.unlink(missing_ok=True)

if __name__=='__main__':asyncio.run(serve(sys.argv[1],sys.argv[2]))
