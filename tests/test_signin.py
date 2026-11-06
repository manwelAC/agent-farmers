import asyncio
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch,AsyncMock
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core.engine import Engine

class SigninTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory();self.engine=Engine(Path(self.temp.name))
        self.spec=dict(id='antigravity',name='Antigravity',command=['fixture'],version='1',environment='WSL',installed=True,auth='CLI available · sign-in unverified',models=[],capabilities={})
        self.engine.store.put('connections',self.spec)
    async def asyncTearDown(self):
        await self.engine.cancel()
        for task in list(self.engine.background):task.cancel()
        await asyncio.gather(*list(self.engine.background),return_exceptions=True)
        self.engine.store.db.close();self.temp.cleanup()
    async def test_login_exit_triggers_refresh_without_model_request(self):
        class Child:
            def poll(self):return 0
        with patch.object(self.engine,'refresh',new_callable=AsyncMock) as refresh,patch('core.providers.verify',new_callable=AsyncMock) as verify:
            self.engine.watch_login('antigravity',Child());await asyncio.sleep(.05)
            refresh.assert_awaited_once();verify.assert_not_awaited()
    async def test_success_survives_refresh_for_same_runtime(self):
        with patch('core.providers.verify',new_callable=AsyncMock):
            self.engine.verify_connection('antigravity');await self.engine.active
        self.assertEqual(self.engine.store.get('connections','antigravity')['auth'],'Session verified')
        with patch('core.providers.discover',new=AsyncMock(return_value={'antigravity':self.spec})),patch('core.providers.inspect',new=AsyncMock(return_value=dict(self.spec))):await self.engine.refresh()
        self.assertEqual(self.engine.store.get('connections','antigravity')['auth'],'Session verified')
    async def test_failed_recheck_clears_old_success(self):
        self.spec['sessionVerifiedAt']='old';self.engine.store.put('connections',self.spec)
        with patch('core.providers.verify',new=AsyncMock(side_effect=ValueError('Sign-in needed'))):
            self.engine.verify_connection('antigravity');await self.engine.active
        value=self.engine.store.get('connections','antigravity')
        self.assertEqual(value['auth'],'Verification failed');self.assertNotIn('sessionVerifiedAt',value)
    async def test_cancel_check_is_not_left_verifying(self):
        async def wait(*args):await asyncio.sleep(60)
        with patch('core.providers.verify',new=wait):
            self.engine.verify_connection('antigravity');await asyncio.sleep(.01);await self.engine.cancel()
        self.assertEqual(self.engine.store.get('connections','antigravity')['auth'],'Verification cancelled')

if __name__=='__main__':unittest.main()
