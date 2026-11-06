import asyncio
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core.engine import Engine,validate_plan
from core.store import Store,workspace,output_path
from core import providers

class EngineTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.engine=Engine(self.root)
        self.patch=patch.dict(os.environ,{'AGENT_FARMERS_TEST_CASE':'success'});self.patch.start()
        self.spec=dict(id='codex',name='Controlled fixture',command=[sys.executable,str(Path(__file__).with_name('fake_runtime.py'))],environment='Windows',installed=True,auth='Signed in',models=[],version='fixture',capabilities={'files':'Fixture only','web':'Unknown','images':'Unknown'})
        self.engine.store.put('connections',self.spec)
        self.worker=self.engine.worker(dict(name='Researcher',provider='codex',role='Original role',skills=[]))
        self.reviewer=self.engine.worker(dict(name='Reviewer',provider='codex',role='Review evidence',skills=[]))
        self.project=self.engine.project(dict(idea='First ask for a topic.',plannerId=self.worker['id']))
        self.tasks=[dict(id='t1',workerId=self.worker['id'],instructions='Write a report on the clarified topic.',outputs=['report.txt'],acceptance='Check the content.',dependsOn=[])]
    async def asyncTearDown(self):
        await self.engine.cancel()
        if self.engine.active and not self.engine.active.done():await asyncio.wait_for(self.engine.active,5)
        self.engine.store.db.close();self.patch.stop();self.temp.cleanup()
    def approve(self,review=False):
        plan=self.engine.plan(self.project['id'],{'brief':'Growtopia inflation over the years, general audience.','tasks':self.tasks})
        return self.engine.approval(self.project['id'],dict(planId=plan['id'],write=True,web=False,reviewerId=self.reviewer['id'] if review else ''))
    async def execute(self,review=False):
        approval=self.approve(review);self.engine.start(self.project['id'],approval['id']);await asyncio.wait_for(asyncio.shield(self.engine.active),30)
        return self.engine.detail(self.project['id'])
    async def test_delivery_and_readonly_review_are_persisted(self):
        detail=await self.execute(True)
        self.assertEqual(detail['project']['status'],'completed');self.assertEqual(len(detail['attempts']),2);self.assertEqual(len(detail['artifacts']),1)
        self.assertEqual(Path(detail['artifacts'][0]['path']).read_text(),'Fixture report')
        note=Path(self.engine.remember(self.project['id']));self.assertIn('Outcome: completed',note.read_text());self.assertEqual(self.engine.remember(self.project['id']),str(note))
    async def test_planning_proposes_but_does_not_approve(self):
        self.engine.discuss(self.project['id'],'Use my clarified scope and draft a plan.')
        await asyncio.wait_for(self.engine.active,5);detail=self.engine.detail(self.project['id'])
        self.assertEqual(detail['project']['status'],'awaiting_approval');self.assertIsNone(detail['project']['approvalId']);self.assertEqual(detail['plan']['tasks'][0]['outputs'],['report.txt'])
        self.assertFalse(list(Path(self.project['folder']).iterdir()))
    async def test_clarifications_and_worker_settings_are_frozen(self):
        p=self.engine.store.get('projects',self.project['id']);p['conversation'].append({'role':'user','text':'Growtopia, general audience, public sources allowed.'});self.engine.store.put('projects',p)
        approval=self.approve();worker=copy.deepcopy(self.worker);worker['role']='Changed later';self.engine.worker(worker)
        self.assertEqual(approval['payload']['workers'][worker['id']]['role'],'Original role')
        payload=approval['payload'];prompt=self.engine.execution_prompt(payload,payload['plan']['tasks'][0],payload['workers'][worker['id']],[])
        self.assertIn('public sources allowed',prompt);self.assertIn('Original role',prompt)
    async def test_plan_edit_invalidates_approval_and_keeps_version(self):
        approval=self.approve();plan=self.engine.plan(self.project['id'],{'tasks':self.tasks,'brief':'Revised scope'})
        self.assertEqual(plan['revision'],2);self.assertEqual(len(self.engine.store.all('plans')),2)
        with self.assertRaises(ValueError):self.engine.start(self.project['id'],approval['id'])
    async def test_missing_output_and_unstructured_answer_are_blocked(self):
        for case in ('missing','unstructured','needs_input','permission'):
            os.environ['AGENT_FARMERS_TEST_CASE']=case
            detail=await self.execute();self.assertEqual(detail['project']['status'],'needs_input' if case=='needs_input' else 'blocked',case)
            self.assertEqual(len(detail['artifacts']),0)
    async def test_one_correction_and_rereview(self):
        os.environ['AGENT_FARMERS_TEST_CASE']='review_changes';detail=await self.execute(True)
        self.assertEqual(detail['project']['status'],'completed');self.assertEqual(len(detail['attempts']),4)
        self.assertEqual(sum(a['stage']=='correction' for a in detail['attempts']),1)
    async def test_unresolved_review_stops_at_budget(self):
        os.environ['AGENT_FARMERS_TEST_CASE']='review_always_changes';detail=await self.execute(True)
        self.assertEqual(detail['project']['status'],'blocked');self.assertEqual(len(detail['attempts']),4)
    async def test_cancel_and_duplicate_dispatch(self):
        os.environ['AGENT_FARMERS_TEST_CASE']='wait';approval=self.approve();self.engine.start(self.project['id'],approval['id'])
        with self.assertRaises(ValueError):self.engine.start(self.project['id'],approval['id'])
        await asyncio.sleep(.2);await self.engine.cancel();await asyncio.wait_for(self.engine.active,5)
        self.assertEqual(self.engine.detail(self.project['id'])['project']['status'],'cancelled')
    async def test_quiet_running_process_has_live_status_and_stops_honestly(self):
        os.environ['AGENT_FARMERS_TEST_CASE']='wait';approval=self.approve();self.engine.start(self.project['id'],approval['id'])
        for _ in range(100):
            if self.engine.process is not None:break
            await asyncio.sleep(.03)
        live=self.engine.detail(self.project['id'])['live']
        self.assertIsNotNone(live);self.assertTrue(live['processRunning']);self.assertEqual(live['worker'],'Researcher')
        self.assertGreaterEqual(live['elapsedSeconds'],0);self.assertIn('Waiting',live['lastActivity'])
        await self.engine.cancel();await asyncio.wait_for(self.engine.active,10)
        self.assertIsNone(self.engine.detail(self.project['id'])['live'])
    async def test_invalid_dependencies_and_paths(self):
        broken=copy.deepcopy(self.tasks);broken[0]['dependsOn']=['t1']
        with self.assertRaises(ValueError):self.engine.plan(self.project['id'],{'tasks':broken})
        with self.assertRaises(ValueError):output_path(self.project['folder'],'../escape.txt')
        with self.assertRaises(ValueError):output_path(self.project['folder'],'C:/escape.txt')
    async def test_tampered_approval_is_not_executed(self):
        a=self.approve();a['payload']['write']=False;self.engine.store.put('approvals',a)
        with self.assertRaises(ValueError):self.engine.start(self.project['id'],a['id'])
    async def test_recovery_never_automatically_repeats_work(self):
        p=self.engine.store.get('projects',self.project['id']);p.update(status='running');self.engine.store.put('projects',p)
        other=Store(self.root)
        try:self.assertEqual(other.get('projects',p['id'])['status'],'interrupted')
        finally:other.db.close()
    async def test_skills_are_dynamic_and_not_tools(self):
        w=copy.deepcopy(self.worker);w['skills']=[dict(name='Citation audit',instructions='Inspect every citation.',enabled=False)];saved=self.engine.worker(w)
        self.assertFalse(saved['skills'][0]['enabled']);self.assertEqual(self.engine.store.get('workers',w['id'])['skills'],saved['skills'])
    async def test_web_request_is_rejected_for_unsupported_adapter(self):
        spec=dict(self.spec,id='antigravity');self.engine.store.put('connections',spec)
        worker=dict(self.worker,provider='antigravity');self.engine.worker(worker)
        plan=self.engine.plan(self.project['id'],{'tasks':self.tasks})
        with self.assertRaisesRegex(ValueError,'Web access'):self.engine.approval(self.project['id'],dict(planId=plan['id'],web=True))
    async def test_mixed_web_and_local_workers_can_be_approved(self):
        spec=dict(self.spec,id='antigravity');self.engine.store.put('connections',spec)
        local=self.engine.worker(dict(self.reviewer,provider='antigravity'))
        tasks=copy.deepcopy(self.tasks)+[dict(id='t2',workerId=local['id'],instructions='Write from the supplied evidence pack.',outputs=['report.md'],acceptance='Cite the evidence.',dependsOn=['t1'])]
        plan=self.engine.plan(self.project['id'],{'tasks':tasks})
        approval=self.engine.approval(self.project['id'],dict(planId=plan['id'],web=True,write=True))
        self.assertTrue(approval['payload']['webByWorker'][self.worker['id']]);self.assertFalse(approval['payload']['webByWorker'][local['id']])
    async def test_assigned_worker_cannot_review_own_plan(self):
        plan=self.engine.plan(self.project['id'],{'tasks':self.tasks})
        with self.assertRaisesRegex(ValueError,'separate worker'):self.engine.approval(self.project['id'],dict(planId=plan['id'],reviewerId=self.worker['id']))

class PolicyTests(unittest.TestCase):
    def test_tool_evidence_is_recorded_without_raw_arguments(self):
        event={'type':'item.completed','item':{'type':'web_search','action':{'query':'private query not to log'}}}
        result=providers.normalize('codex',event)
        self.assertIn('web_search',result['text']);self.assertNotIn('private query',result['text']);self.assertEqual(result['final'],'')
    def test_provider_commands_do_not_bypass_access(self):
        for provider in providers.LABELS:
            spec={'id':provider,'command':['fixture']};worker={'model':''}
            args,_=providers.build(spec,worker,'C:/workspace',False)
            self.assertFalse(any('dangerously' in a or 'danger-full-access' in a for a in args))
            if provider=='codex':self.assertIn('default_permissions=":read-only"',args)
    def test_reference_projects_are_protected(self):
        for name in ('agentplace','boti-bot'):
            path=Path.home()/'projects'/name
            if path.exists():
                with self.assertRaises(ValueError):workspace(path)

if __name__=='__main__':unittest.main()
