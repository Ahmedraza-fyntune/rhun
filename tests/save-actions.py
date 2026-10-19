#!/usr/bin/env python3
"""Source actions on save: ordering, intermediate authority, deadlines and cancellation."""
import json
import re
import time
import unittest

host=__import__('ext-host')

class SaveActions(host.Host):
    def setUp(self):
        super().setUp()
        self.base_config=(self.work/'config/rhun/config').read_text()

    def tearDown(self):
        for _ in range(20):
            try: return super().tearDown()
            except OSError: time.sleep(.05)
        super().tearDown()

    def providers(self, kinds='source.fixAll', owners=('alice',), mode='edit', delay=0, timeout=2000, formatting=False):
        config=self.work/'config/rhun/config'
        config.write_text(self.base_config+f'\n[files]\ncode_actions_on_save = {kinds}\ncode_actions_on_save_timeout = {timeout}\nformat_on_save = {str(formatting).lower()}\n')
        root=self.work/'sources'
        for owner in owners:
            folder=root/owner/'source'
            folder.mkdir(parents=True,exist_ok=True)
            log=self.work/f'state/rhun/extensions/{owner}--source/source.log'
            if log.exists(): log.unlink()
            (folder/'extension.ini').write_text(
                f'name = source\nowner = {owner}\ntitle = Source actions\nversion = 1\nprotocol = 1\n'
                'runtime = python3\nrun = main.py\non = command\n[needs]\ndocuments = write\n'
                '[provides]\nsave_actions = *\n'+('format = *\n' if formatting else ''))
            (folder/'main.py').write_text('MODE='+json.dumps(mode)+'\nDELAY='+repr(delay)+'\nOWNER='+json.dumps(owner)+'\n'+r'''
import os, sys, time
from pathlib import Path
log=open(Path(os.environ['RHUN_STATE'])/'source.log','a',buffering=1)
print('hello 1 save-actions format' if MODE!='unnegotiated' else 'hello 1 format',flush=True)
pending=None

def send(line,body=None):
    print(line,flush=True)
    if body is not None: sys.stdout.write(body);sys.stdout.flush()

def edit(doc,version,text,foreign=False):
    target='#'+doc
    body=f'1\n{len(target)} {version} 1\n{target}1 1 1 1 {len(text)}\n{text}'
    if foreign:
        path=str(Path(os.environ['RHUN_PROJECT'])/'b.go')
        body=f'2\n{len(target)} {version} 1\n{target}1 1 1 1 {len(text)}\n{text}{len(path)} - 1\n{path}1 1 1 1 1\nQ'
    return body

for raw in sys.stdin.buffer:
    line=raw.decode().rstrip('\n');log.write(line+'\n');f=line.split()
    if len(f)>4 and f[:2]==['0','edits']: sys.stdin.buffer.read(int(f[4]))
    if len(f)>1 and f[1]=='save-actions':
        time.sleep(DELAY)
        if MODE=='hang': continue
        if MODE=='error': send('error '+f[0]+' refused failed');continue
        if MODE in ('empty','unnegotiated'): send('ok '+f[0]+' 0');continue
        body=edit(f[2],f[3],'['+OWNER+']',MODE in ('foreign','foreign-intermediate'))
        if MODE in ('intermediate','late','wrong-request','stale','foreign-intermediate','ordinary','overflow-document','overflow-version'):
            request=f[0] if MODE!='wrong-request' else str(int(f[0])+100)
            version=f[3] if MODE!='stale' else str(int(f[3])+1)
            if MODE=='ordinary': send('101 apply '+str(len(body)),body)
            else:
                doc=f[2] if MODE!='overflow-document' else '18446744073709551617'
                if MODE=='overflow-version': version='18446744073709551617'
                send(f'101 save-apply {request} {doc} {version} {len(body)}',body)
            pending=f[0]
        else: send('ok '+f[0]+' '+str(len(body)),body)
    elif len(f)>1 and f[1]=='format':
        body=edit(f[2],f[3],'F');send('ok '+f[0]+' '+str(len(body)),body)
    elif len(f)>1 and f[0] in ('ok','error') and f[1]=='101' and pending:
        send('ok '+pending+' 0');pending=None
    if f[:2]==['0','bye']: break
''')
        return root

    def source_log(self,owner='alice'):
        path=self.work/f'state/rhun/extensions/{owner}--source/source.log'
        return path.read_text() if path.exists() else ''

    def saved(self): return (self.proj/'a.txt').read_text()

    def test_source_before_format_then_write(self):
        root=self.providers(formatting=True)
        out=self.run_editor(['type y','cmd save','wait 800','print-state'],exts=root)
        self.assertEqual(self.saved(),'F[alice]yhello world\nsecond line\n',out)
        log=self.source_log()
        requests=re.findall(r'(?m)^[1-9]\d* (save-actions|format) ',log)
        self.assertEqual(requests,['save-actions','format'])

    def test_provider_order_is_qualified_lexical(self):
        root=self.providers(owners=('z','a','a-'))
        self.run_editor(['type y','cmd save','wait 1000'],exts=root)
        self.assertEqual(self.saved(),'[z][a][a-]yhello world\nsecond line\n')

    def test_intermediate_credit_is_applied_before_format(self):
        root=self.providers(mode='intermediate',formatting=True)
        self.run_editor(['type y','cmd save','wait 800'],exts=root)
        self.assertEqual(self.saved(),'F[alice]yhello world\nsecond line\n')
        self.assertRegex(self.source_log(),r'(?m)^ok 101 \d+$')

    def test_invalid_intermediate_authority_changes_nothing(self):
        for mode in ('wrong-request','stale','foreign-intermediate','overflow-document','overflow-version'):
            with self.subTest(mode=mode):
                root=self.providers(mode=mode,formatting=True)
                out=self.run_editor(['type y','cmd save','wait 700','print-tabs'],exts=root)
                self.assertEqual(self.saved(),'Fyhello world\nsecond line\n',out)
                self.assertRegex(self.source_log(),r'(?m)^error 101 (refused|stale|syntax) ')
                self.assertFalse(any('b.go' in line for line in out),out)
                (self.proj/'a.txt').write_text('hello world\nsecond line\n')
                import shutil
                shutil.rmtree(root)

    def test_error_and_foreign_final_skip_remaining_sources_but_format(self):
        for mode in ('error','foreign'):
            with self.subTest(mode=mode):
                root=self.providers(mode=mode,formatting=True,kinds='source.fixAll source.organizeImports')
                self.run_editor(['type y','cmd save','wait 700'],exts=root)
                self.assertEqual(self.saved(),'Fyhello world\nsecond line\n')
                self.assertEqual(self.source_log().count(' save-actions '),1)
                (self.proj/'a.txt').write_text('hello world\nsecond line\n')
                import shutil
                shutil.rmtree(root)

    def test_timeout_rejects_late_intermediate_edit(self):
        root=self.providers(mode='late',delay=.6,timeout=250,formatting=False)
        self.run_editor(['type y','cmd save','wait 1100','print-doc'],exts=root)
        self.assertEqual(self.saved(),'yhello world\nsecond line\n')
        self.assertIn('error 101 refused ',self.source_log())

    def test_cancel_rejects_late_intermediate_and_does_not_write(self):
        root=self.providers(mode='late',delay=.5)
        self.run_editor(['type y','cmd save','wait 100','cmd cancel_save','wait 800'],exts=root)
        self.assertEqual(self.saved(),'hello world\nsecond line\n')
        self.assertIn('0 cancel ',self.source_log())
        self.assertIn('error 101 refused ',self.source_log())

    def test_typing_during_source_phase_skips_source_and_formatter(self):
        root=self.providers(delay=.4,formatting=True)
        self.run_editor(['type y','cmd save','wait 100','type z','wait 800'],exts=root)
        self.assertEqual(self.saved(),'yzhello world\nsecond line\n')
        self.assertNotRegex(self.source_log(),r'(?m)^[1-9]\d* format ')

    def test_ordinary_apply_is_not_credited(self):
        root=self.providers(mode='ordinary',formatting=True)
        self.run_editor(['type y','cmd save','wait 800'],exts=root)
        self.assertEqual(self.saved(),'[alice]yhello world\nsecond line\n')
        self.assertNotRegex(self.source_log(),r'(?m)^[1-9]\d* format ')

    def test_bypass_skips_all_participants(self):
        root=self.providers(formatting=True)
        self.run_editor(['type y','cmd save_without_formatting','wait 700'],exts=root)
        self.assertEqual(self.saved(),'yhello world\nsecond line\n')
        self.assertNotIn(' save-actions ',self.source_log())
        self.assertNotRegex(self.source_log(),r'(?m)^[1-9]\d* format ')

    def test_empty_and_unnegotiated_provider_are_quiet(self):
        root=self.providers(mode='empty')
        self.run_editor(['type y','cmd save','wait 500','print-toast'],exts=root)
        self.assertEqual(self.saved(),'yhello world\nsecond line\n')
        self.assertEqual(self.source_log().count(' save-actions '),1)

    def test_ancestor_kinds_and_duplicate_kinds_are_run_once(self):
        root=self.providers(kinds='source.fixAll.eslint source.organizeImports source.fixAll source.fixAll')
        self.run_editor(['type y','cmd save','wait 800'],exts=root)
        requests=[s.split()[-1] for s in self.source_log().splitlines() if ' save-actions ' in s]
        self.assertEqual(requests,['source.organizeImports','source.fixAll'])


    def test_unnegotiated_and_user_stopped_providers_are_skipped(self):
        root=self.providers(mode='unnegotiated')
        self.run_editor(['type y','cmd save','wait 500'],exts=root)
        self.assertEqual(self.saved(),'yhello world\nsecond line\n')
        self.assertNotIn(' save-actions ',self.source_log())
        root=self.providers()
        (self.proj/'a.txt').write_text('hello world\nsecond line\n')
        self.run_editor(['wait 200','ext-set alice/source stop','wait 200','type y','cmd save','wait 500'],exts=root)
        self.assertEqual(self.saved(),'yhello world\nsecond line\n')
        self.assertNotIn(' save-actions ',self.source_log())

    def test_invalid_config_preserves_previous_valid_candidate(self):
        invalid=['quickfix','source.','source..x','source.é','source.x y','source.'+'x'*122,
                 ' '.join('source.x'+str(i) for i in range(33)), 'source.'+'x'*4096]
        for candidate in invalid:
            with self.subTest(candidate=candidate[:40]):
                root=self.providers(kinds='source.fixAll')
                config=self.work/'config/rhun/config'
                config.write_text(config.read_text()+'code_actions_on_save = '+candidate+'\n')
                (self.proj/'a.txt').write_text('hello world\nsecond line\n')
                self.run_editor(['type y','cmd save','wait 400'],exts=root)
                requests=re.findall(r'(?m)^[1-9]\d* save-actions \d+ \d+ (\S+)',self.source_log())
                self.assertEqual(requests,['source.fixAll'])
                self.assertIn('code_actions_on_save = source.fixAll\n',config.read_text())

    def test_duplicate_saves_coalesce_source_phase(self):
        root=self.providers(delay=.25)
        self.run_editor(['type y','cmd save','cmd save','wait 800'],exts=root)
        self.assertEqual(self.saved(),'[alice]yhello world\nsecond line\n')
        self.assertEqual(self.source_log().count(' save-actions '),1)

    def test_save_all_uses_each_document(self):
        root=self.providers()
        out=self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z','cmd save_all','wait 1000'],exts=root)
        self.assertEqual(self.saved(),'[alice]yhello world\nsecond line\n',out)
        self.assertEqual((self.proj/'b.go').read_text(),'[alice]zpackage b\n',out)


    def test_source_provider_requires_document_write_authority(self):
        for permission in ('read','none'):
            with self.subTest(permission=permission):
                root=self.providers()
                manifest=root/'alice/source/extension.ini'
                manifest.write_text(manifest.read_text().replace('documents = write','documents = '+permission))
                (self.proj/'a.txt').write_text('hello world\nsecond line\n')
                self.run_editor(['type y','cmd save','wait 500'],exts=root)
                self.assertEqual(self.saved(),'yhello world\nsecond line\n')
                self.assertNotIn(' save-actions ',self.source_log())

for name in dir(host.Host):
    if name.startswith('test_'): setattr(SaveActions,name,None)

if __name__=='__main__': unittest.main()
