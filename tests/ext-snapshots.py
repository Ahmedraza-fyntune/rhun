#!/usr/bin/env python3
"""Document event ordering around a whole-text snapshot."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT/'build/rhun')).resolve()
PEER = r'''
import json, os, sys
from pathlib import Path
log = open(Path(os.environ['RHUN_STATE'])/'trace.jsonl', 'w', buffering=1)
print('hello 1', flush=True)
versions = {}
large = (Path(os.environ['RHUN_STATE'])/'large').exists()
def send(data):
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()
while True:
    line = sys.stdin.buffer.readline()
    if not line: break
    fields = line.decode().rstrip('\n').split()
    body = b''
    if fields[0]=='ok' and fields[1] in ('22','24','25'):
        body = sys.stdin.buffer.read(int(fields[3]))
    elif fields[0]=='0' and fields[1]=='edits':
        body = sys.stdin.buffer.read(int(fields[4]))
    log.write(json.dumps({'line':' '.join(fields), 'body':body.decode()})+'\n')
    if fields[:2]==['0','opened']:
        versions[fields[2]]=int(fields[3])
    elif fields[:2]==['0','run']:
        doc=fields[3]
        data=b'A'*((1<<20)+1) if large else b'A'
        send(f'21 replace {doc} {versions[doc]} 1 1 1 1 {len(data)}\n'.encode()+data+f'22 text {doc}\n'.encode())
    elif fields[:2]==['ok','22']:
        send(f'23 replace {doc} {fields[2]} 1 1 1 1 1\nB24 text {doc}\n25 text {doc}\n'.encode())
    elif fields[:2]==['0','bye']:
        break
'''

class Snapshots(unittest.TestCase):
    def run_peer(self, large=False):
        with tempfile.TemporaryDirectory(prefix='rhun-snapshot-') as tmp:
            work=Path(tmp).resolve()
            project=work/'project'
            project.mkdir()
            (project/'a.txt').write_text('hello\n')
            config=work/'config/rhun'
            config.mkdir(parents=True)
            (config/'config').write_text('[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n[git]\nenabled = false\n')
            extension=work/'extensions/rhun-tests/snapshot'
            extension.mkdir(parents=True)
            (extension/'peer.py').write_text(PEER)
            (extension/'extension.ini').write_text('name = snapshot\nowner = rhun-tests\ntitle = Snapshot\nversion = 1\nprotocol = 1\nruntime = python3\nrun = peer.py\non = command\n[commands]\nprobe = Probe\n[subscribe]\nopened = *\nedits = *\n[needs]\ndocuments = write\nproject = read\n')
            state=work/'state/rhun/extensions/rhun-tests--snapshot'
            state.mkdir(parents=True)
            if large: (state/'large').touch()
            script=work/'actions.txt'
            script.write_text(f'open {project}/a.txt\ncmd snapshot.probe\nwait 1600\nquit\n')
            env=dict(os.environ,HOME=str(work),XDG_CONFIG_HOME=str(work/'config'),XDG_STATE_HOME=str(work/'state'))
            result=subprocess.run([str(EXE),str(project),'--headless','1000x600','--extensions',str(work/'extensions'),'--script',str(script)],env=env,capture_output=True,timeout=20)
            self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
            trace=state/'trace.jsonl'
            self.assertTrue(trace.exists(),result.stderr.decode(errors='replace'))
            return [json.loads(line) for line in trace.read_text().splitlines()]

    def test_edit_batches_do_not_overlap_text_snapshot(self):
        trace=self.run_peer()
        first=next(i for i,x in enumerate(trace) if x['line'].startswith('ok 22 '))
        second=next(i for i,x in enumerate(trace) if x['line'].startswith('ok 24 '))
        self.assertEqual(trace[first]['body'],'Ahello\n')
        self.assertEqual(trace[second]['body'],'BAhello\n')
        before=[x for x in trace[:first] if x['line'].startswith('0 edits ')]
        after=[x for x in trace[first+1:second] if x['line'].startswith('0 edits ')]
        self.assertEqual([x['body'] for x in before],['0 0 1\nA'])
        self.assertEqual([x['body'] for x in after],['0 0 1\nB'])

    def test_same_version_resync_is_not_repeated_by_text_reads(self):
        trace=self.run_peer(large=True)
        first=next(i for i,x in enumerate(trace) if x['line'].startswith('ok 22 '))
        resync=[x['line'] for x in trace if x['line'].startswith('0 resync ')]
        self.assertEqual(len(resync),1,resync)
        self.assertTrue(any(x['line'].startswith('0 resync ') for x in trace[:first]))
        final=next(x for x in trace if x['line'].startswith('ok 25 '))
        self.assertEqual(final['body'],'B'+'A'*((1<<20)+1)+'hello\n')

if __name__=='__main__':
    unittest.main()
