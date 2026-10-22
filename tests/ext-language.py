#!/usr/bin/env python3
"""Language-only changes preserve intent and reject delayed provider edits."""
import unittest
host=__import__('ext-host')
saves=__import__('save')
providers=__import__('ext-providers')

class Languages(host.Host):
    def choose(self, name):
        return ['cmd select_language','type '+name,'key Return']

    def test_manual_plain_and_automatic_survive_save_as(self):
        empty=self.work/'empty';empty.mkdir()
        target=self.proj/'copy.rs'
        out=self.run_editor([
            *self.choose('Python'),'print-state',
            'cmd save_as','key ctrl+a','type '+str(target),'key Return','wait 100','print-state',
            *self.choose('Automatic'),'print-state',
            *self.choose('Plain Text'),'print-state','cmd save','print-state',
            *self.choose('Automatic'),'print-state'],exts=empty,files=('b.go',))
        states=[line for line in out if line.startswith('tabs=')]
        self.assertEqual(len(states),6,out)
        for state,language in zip(states,('Python','Python','Rust','none','none','Rust')):
            self.assertIn('lang='+language+' ',state,out)
        self.assertEqual(target.read_text(),'package b\n')

    def test_language_change_during_save_keeps_latest_text_and_drops_format(self):
        root=saves.Saves.formatter(self,delay=.5)
        out=self.run_editor(['type y','cmd save','wait 150',*self.choose('Python'),
            'wait 800','print-state','print-doc'],exts=root)
        self.assertIn(' format ',saves.Saves.requests(self))
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn('yhello world',out)
        self.assertFalse(any(line.startswith('Xyhello') for line in out),out)
        self.assertTrue(any(' dirty=0 ' in line for line in out if line.startswith('tabs=')),out)

    def test_language_change_drops_delayed_explicit_format(self):
        root=saves.Saves.formatter(self,delay=.5)
        out=self.run_editor(['cmd format_document','wait 150',*self.choose('Python'),
            'wait 800','print-doc'],exts=root)
        self.assertIn(' format ',saves.Saves.requests(self))
        self.assertIn('hello world',out)
        self.assertFalse(any(line.startswith('Xhello') for line in out),out)

    def test_language_change_cancels_cold_provider_action(self):
        root=providers.Providers.extensions(self,owners=('alice',),delay=.5)
        out=self.run_editor(['cmd format_document','wait 100',*self.choose('Python'),
            'wait 800','print-extensions'],exts=root)
        self.assertNotIn(' format ',providers.Providers.requests(self,'alice'))
        self.assertTrue(any('state=running' in line for line in out),out)

    def test_existing_document_language_starts_idle_language_extension(self):
        root=self.work/'observers';folder=root/'fixture'/'observer';folder.mkdir(parents=True)
        (folder/'extension.ini').write_text('owner = fixture\nname = observer\ntitle = Observer\n'
            'version = 1\nprotocol = 1\nruntime = python3\nrun = main.py\non = lang:Python\n')
        (folder/'main.py').write_text("import sys\nprint('hello 1',flush=True)\nfor line in sys.stdin:\n if line.startswith('0 bye'):break\n")
        out=self.run_editor(['print-extensions',*self.choose('Python'),'wait 500','print-extensions'],exts=root)
        self.assertTrue(any('state=idle' in line for line in out),out)
        self.assertTrue(any('state=running' in line for line in out),out)

    def test_language_only_reopen_replays_active_cursor_and_selection(self):
        root=self.manifest_variant('reopen',**{'hover = *':'hover = *\nselection = *'})
        self.run_editor(['cmd echo.toast','wait-ext echo running','wait 100',
            'key ctrl+Home',*(['key shift+Right']*5),*self.choose('Python'),'wait 300'],exts=root)
        log=self.echo_log()
        opened='0 opened 1 0 Python '+(self.proj/'a.txt').as_posix()
        at=log.index(opened)
        self.assertIn('0 closed 1',log[:at])
        tail=log[at+1:]
        active=tail.index('0 active 1')
        cursor=tail.index('0 cursor 1 1 6')
        selection=tail.index('0 selection 1 1 1 1 6')
        self.assertLess(active,cursor,log)
        self.assertLess(cursor,selection,log)

for name in dir(host.Host):
    if name.startswith('test_'):setattr(Languages,name,None)

if __name__=='__main__':unittest.main()
