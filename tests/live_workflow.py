"""Opt-in live check: local-source analysis, real file output and independent review."""
import argparse
import asyncio
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core.engine import Engine

async def main():
    parser=argparse.ArgumentParser();parser.add_argument('--data-dir',required=True);parser.add_argument('--provider',choices=['codex','antigravity'],default='codex');parser.add_argument('--reviewer',choices=['codex','antigravity'],default='antigravity');args=parser.parse_args()
    engine=Engine(Path(args.data_dir));await engine.refresh()
    try:
        writer=engine.worker(dict(name='Evidence writer',provider=args.provider,model='',role='Analyze supplied evidence only. No web access, no invented sources.',skills=[dict(name='Source discipline',instructions='Cite the supplied filename and distinguish observation from interpretation.',enabled=True)]))
        reviewer=engine.worker(dict(name='Independent reviewer',provider=args.reviewer,model='',role='Read the source and output. Check claims and source citations.',skills=[]))
        project=engine.project(dict(idea='From source.txt, write a short evidence-based report explaining the change in demand. This is a disposable integration test, not real-world research.',plannerId=writer['id']))
        (Path(project['folder'])/'source.txt').write_text('Synthetic evidence for a software test, not a real market.\nJanuary: 100 units sold at 10 credits each.\nFebruary: 80 units sold at 10 credits each.\nNo information about causes was collected.\n',encoding='utf-8')
        plan=engine.plan(project['id'],{'brief':'Summarize the supplied synthetic evidence. Sales volume fell by 20%; unit price stayed unchanged. Causes are unknown. Do not describe this as price inflation or claim a cause.','tasks':[dict(id='analysis',workerId=writer['id'],instructions='Read source.txt using your normal authorized local file tools and write report.md with observations, the percentage change calculation, a source citation and limitations. Do not modify source.txt or use external sources.',outputs=['report.md'],acceptance='The report cites source.txt, states sales volume fell 20%, price was unchanged and causes are unknown.',dependsOn=[])]})
        approval=engine.approval(project['id'],dict(planId=plan['id'],write=True,web=False,reviewerId=reviewer['id']))
        engine.start(project['id'],approval['id'])
        try:await asyncio.wait_for(asyncio.shield(engine.active),180)
        except asyncio.TimeoutError:await engine.cancel();await engine.active
        detail=engine.detail(project['id'])
        print(json.dumps({'status':detail['project']['status'],'activity':detail['project']['activity'],'attempts':[{k:a.get(k) for k in ('workerName','provider','stage','status','summary','usage')} for a in detail['attempts']],'artifacts':detail['artifacts']},indent=2),flush=True)
        report=Path(project['folder'])/'report.md'
        valid=detail['project']['status']=='completed' and report.is_file() and '20' in report.read_text(encoding='utf-8') and 'source.txt' in report.read_text(encoding='utf-8')
        return 0 if valid else 1
    finally:
        await engine.cancel();engine.store.db.close()
if __name__=='__main__':sys.exit(asyncio.run(main()))
