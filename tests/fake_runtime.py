"""Controlled process fixture, never advertised as a real connection."""
import json
import os
from pathlib import Path
import sys
import time

prompt=sys.stdin.read()
case=os.environ.get('AGENT_FARMERS_TEST_CASE','success')
if case=='wait':time.sleep(60)
if case=='permission':
    print('read_file permission auto-denied in noninteractive mode',file=sys.stderr,flush=True)
    answer=''
elif prompt.find('Planning only:')>=0:
    roster=json.JSONDecoder().raw_decode(prompt.split('Workers: ',1)[1])[0]
    answer=json.dumps({'reply':'Assume a small offline report.','brief':'Write a report from supplied evidence.','tasks':[{'id':'t1','workerId':roster[0]['id'],'instructions':'Write the report.','outputs':['report.txt'],'acceptance':'Read the report','dependsOn':[]}]})
elif 'Independent READ-ONLY review.' in prompt:
    verdict='blocked' if case=='review_blocked' else 'changes_requested' if case in ('review_changes','review_always_changes') and ('corrected' not in prompt or case=='review_always_changes') else 'pass'
    answer=json.dumps({'verdict':verdict,'summary':'Fixture checked the report.','issues':['Correct the report'] if verdict=='changes_requested' else []})
else:
    if case not in ('missing','blocked','needs_input','unstructured'):
        Path('report.txt').write_text('Fixture report; corrected' if 'One approved correction' in prompt else 'Fixture report',encoding='utf-8')
    status='blocked' if case=='blocked' else 'needs_input' if case=='needs_input' else 'completed'
    answer='What should I do?' if case=='unstructured' else json.dumps({'status':status,'summary':'corrected fixture' if 'One approved correction' in prompt else 'Fixture report delivered','question':'Provide the source document' if status=='needs_input' else ''})
print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':answer}}),flush=True)
print(json.dumps({'type':'turn.completed','usage':{'input_tokens':10,'output_tokens':5}}),flush=True)
