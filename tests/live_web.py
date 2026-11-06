"""Opt-in minimal native Codex web-tool check; consumes subscription usage."""
import asyncio
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core.engine import Engine

async def main():
    engine=Engine(Path(sys.argv[1]));await engine.refresh()
    try:
        worker=engine.worker(dict(name='Web researcher',provider='codex',role='Use the runtime native web search tool. Use only official Godot sources. Disclose missing tools; do not substitute memory for a current lookup.',skills=[]))
        p=engine.project(dict(idea='Verify the current stable Godot Windows version from the official download page. This is a small connectivity test.',plannerId=worker['id']))
        plan=engine.plan(p['id'],{'brief':'Check https://godotengine.org/download/windows/ using the runtime native web search tool. Write web-check.md with the current stable version, source URL, retrieval date and any access limits. Do not claim a live lookup if the tool is missing.','tasks':[dict(id='web',workerId=worker['id'],instructions='Use native web search to access the official Godot Windows download page and write the short verification note. No other research or changes.',outputs=['web-check.md'],acceptance='The answer includes the official source URL and explicitly states what was accessed.',dependsOn=[])]})
        a=engine.approval(p['id'],dict(planId=plan['id'],write=True,web=True));engine.start(p['id'],a['id'])
        try:await asyncio.wait_for(asyncio.shield(engine.active),120)
        except asyncio.TimeoutError:await engine.cancel();await engine.active
        detail=engine.detail(p['id']);web_events=[e for e in detail['events'] if 'web_search' in e['data'].get('text','')]
        print(json.dumps({'status':detail['project']['status'],'activity':detail['project']['activity'],'webToolEvents':len(web_events),'attempts':[{k:r.get(k) for k in ('status','summary','usage')} for r in detail['attempts']]},indent=2),flush=True)
        return 0 if detail['project']['status']=='completed' and web_events else 1
    finally:await engine.cancel();engine.store.db.close()
if __name__=='__main__':sys.exit(asyncio.run(main()))
