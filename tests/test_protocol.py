import asyncio
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import sqlite3
import unittest
import aiohttp

ROOT=Path(__file__).resolve().parents[1]

class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory();self.data=Path(self.temp.name);self.session=self.data/'session.json'
        self.log=(self.data/'runtime.log').open('w')
        self.process=subprocess.Popen([sys.executable,str(ROOT/'launch.py'),'--core',str(self.data),str(self.session)],stdout=self.log,stderr=self.log,creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32' else 0)
        for _ in range(150):
            if self.session.exists():break
            if self.process.poll() is not None:self.fail('Core exited before becoming ready')
            await asyncio.sleep(.05)
        self.assertTrue(self.session.exists());self.info=json.loads(self.session.read_text());self.base='http://127.0.0.1:'+str(self.info['port'])
        self.client=aiohttp.ClientSession(headers={'Authorization':'Bearer '+self.info['token']})
    async def asyncTearDown(self):
        try:
            async with self.client.post(self.base+'/v1/command',json={'action':'shutdown'}):pass
        finally:
            await self.client.close()
            try:await asyncio.to_thread(self.process.wait,15)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
            self.log.close();self.temp.cleanup()
    async def test_authentication_origin_and_versioned_state(self):
        async with aiohttp.ClientSession() as other:
            async with other.get(self.base+'/v1/state') as response:self.assertEqual(response.status,401)
        async with self.client.get(self.base+'/v1/state',headers={'Origin':'https://example.com'}) as response:self.assertEqual(response.status,403)
        async with self.client.get(self.base+'/v1/state') as response:
            value=await response.json();self.assertEqual(response.status,200);self.assertEqual(value['version'],1);self.assertEqual(value['workers'],[])
    async def test_websocket_and_project_lifecycle(self):
        async with self.client.ws_connect(self.base+'/v1/events') as ws:
            async with self.client.post(self.base+'/v1/command',json={'action':'worker.save','payload':{'name':'User worker','provider':'codex','role':'Research','skills':[]}}) as response:worker=(await response.json())['result']
            event=await ws.receive_json(timeout=5);self.assertEqual(event['kind'],'workers')
            async with self.client.post(self.base+'/v1/command',json={'action':'project.create','payload':{'idea':'Investigate supplied evidence','plannerId':worker['id']}}) as response:p=(await response.json())['result']
            async with self.client.get(self.base+'/v1/projects/'+p['id']) as response:detail=await response.json()
            self.assertEqual(detail['project']['status'],'draft');self.assertIsNone(detail['approval']);self.assertEqual(detail['attempts'],[])
            async with self.client.post(self.base+'/v1/command',json={'action':'project.start','payload':{'id':p['id'],'approvalId':'invented'}}) as response:self.assertEqual(response.status,400)
    async def test_artifact_preview_and_workspace_boundary(self):
        async with self.client.post(self.base+'/v1/command',json={'action':'worker.save','payload':{'name':'Fixture','provider':'codex','skills':[]}}) as response:w=(await response.json())['result']
        async with self.client.post(self.base+'/v1/command',json={'action':'project.create','payload':{'idea':'Artifact preview fixture','plannerId':w['id']}}) as response:p=(await response.json())['result']
        report=Path(p['folder'])/'report.md';report.write_text('# A report\nNot executable HTML.',encoding='utf-8')
        db=sqlite3.connect(self.data/'farmers.sqlite3')
        for identifier,relative in (('safe','report.md'),('unsafe','../escape.md')):
            db.execute('INSERT INTO artifacts VALUES(?,?)',(identifier,json.dumps(dict(id=identifier,projectId=p['id'],relative=relative,path=str(report)))))
        db.commit();db.close()
        async with self.client.get(self.base+'/v1/artifacts/safe/preview') as response:
            value=await response.json();self.assertEqual(value['kind'],'text');self.assertIn('# A report',value['text'])
        async with self.client.get(self.base+'/v1/artifacts/unsafe/preview') as response:self.assertEqual(response.status,400)

if __name__=='__main__':unittest.main()
