#!/usr/bin/env python3
"""Managed saves and formatter edits preserve document and interaction context."""
import re
import json
import os
import time
import unittest

host = __import__('ext-host')


def workspace(groups):
    body = str(len(groups))+'\n'
    for path, version, edits in groups:
        body += f'{len(path.encode())} {version} {len(edits)}\n'+path
        for l1,c1,l2,c2,text in edits:
            body += f'{l1} {c1} {l2} {c2} {len(text.encode())}\n'+text
    return body


class Saves(host.Host):
    def tearDown(self):
        for _ in range(20):
            try:
                return super().tearDown()
            except OSError:
                time.sleep(.05)
        super().tearDown()

    def formatter(self, mode='ok', delay=0, owners=('alice',), timeout=2000, on='command'):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text()+f'\n[files]\nformat_on_save = true\nformat_on_save_timeout = {timeout}\n')
        root=self.work/'formatters'
        for owner in owners:
            folder=root/owner/'format'
            folder.mkdir(parents=True)
            (folder/'extension.ini').write_text(
                f'name = format\nowner = {owner}\ntitle = Formatter\nversion = 1\nprotocol = 1\n'
                f'runtime = python3\nrun = main.py\non = {on}\n[needs]\ndocuments = write\n'
                '[provides]\nformat = *\n')
            program = r'''
import sys, time, os
from pathlib import Path
# bodies are counted in bytes: no CRLF translation or code page on Windows
sys.stdout.reconfigure(encoding='utf-8', newline='\n')
log = open(Path(os.environ['RHUN_STATE'])/'requests.log','a',buffering=1)
print('hello 1 format',flush=True)
for raw in sys.stdin.buffer:
    line=raw.decode()
    log.write(line)
    words=line.split()
    if len(words)>4 and words[:2]==['0','edits']:
        sys.stdin.buffer.read(int(words[4]))
    if len(words)>1 and words[1]=='format':
        if len(words)!=6 or words[5] not in ('yes','no'):
            print('error '+words[0]+' syntax invalid format options',flush=True)
            continue
        time.sleep(DELAY)
        if MODE=='error':
            print('error '+words[0]+' failed formatter failed',flush=True)
            continue
        if MODE=='empty':
            print('ok '+words[0]+' 0',flush=True)
            continue
        if MODE=='hang': continue
        path='#'+words[2]
        if MODE=='foreign': path=FOREIGN
        version=words[3] if MODE!='foreign' else '-'
        body=f'1\n{len(path.encode())} {version} 1\n{path}1 1 1 1 1\nX'
        print('ok '+words[0]+' '+str(len(body.encode())),flush=True)
        sys.stdout.write(body)
        sys.stdout.flush()
    if line.startswith('0 bye'): break
'''
            (folder/'main.py').write_text(
                f'MODE={json.dumps(mode)}\nDELAY={delay!r}\nFOREIGN={json.dumps(str(self.proj/"foreign.txt"))}\n'+program)
        return root

    def requests(self, owner='alice'):
        path=self.work/f'state/rhun/extensions/{owner}--format/requests.log'
        return path.read_text() if path.exists() else ''

    def edit(self, groups=None):
        path=self.work/'edit.txt'
        path.write_text(workspace(groups or [('#1',0,[(1,1,1,1,'X')])]))
        return path.as_posix()

    def states(self,out):
        return [line for line in out if line.startswith('tabs=')]

    def test_restricted_edit_preserves_palette_and_prompt(self):
        for command in ('command_palette','save_as'):
            with self.subTest(command=command):
                out=self.run_editor(['cmd '+command,'print-state','print-palette',
                    'apply-document 1 '+self.edit(),'print-state','print-palette','print-doc'])
                states=self.states(out)
                self.assertEqual(re.search(r'focus=\d+',states[0]).group(),re.search(r'focus=\d+',states[1]).group(),out)
                palettes=[line for line in out if line.startswith(('mode=','palette=','prompt='))]
                half=len(palettes)//2
                self.assertEqual(palettes[:half],palettes[half:],out)
                self.assertIn('Xhello world',out)

    def test_restricted_edit_preserves_terminal_focus(self):
        out=self.run_editor(['cmd toggle_terminal','wait 100','print-state',
            'apply-document 1 '+self.edit(),'print-state','print-doc'])
        self.assertTrue(all('focus=8 ' in state for state in self.states(out)),out)
        self.assertIn('Xhello world',out)

    def test_restricted_edit_preserves_vim_insert_mode(self):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text()+'\n[editor]\nvim_mode = true\n')
        out=self.run_editor(['key i','print-state','apply-document 1 '+self.edit(),
            'print-state','type y','print-doc'])
        states=self.states(out)
        self.assertEqual(re.search(r'vim=\w+',states[0]).group(),re.search(r'vim=\w+',states[1]).group(),out)
        self.assertIn('yXhello world',out)

    def test_restricted_edit_keeps_inactive_tab_and_scroll(self):
        (self.proj/'b.go').write_text('package b\n'+''.join('// line\n' for _ in range(1000)))
        out=self.run_editor(['key ctrl+End','scroll 10','print-state','print-scroll',
            'apply-document 1 '+self.edit(),'print-state','print-scroll',
            'open '+(self.proj/'a.txt').as_posix(),'print-doc'],files=('a.txt','b.go'))
        states=self.states(out)
        self.assertIn('active=b.go',states[0])
        self.assertEqual(states[0],states[1],out)
        scroll=[line for line in out if line.startswith('x=')]
        self.assertEqual(scroll[:1],scroll[1:],out)
        self.assertIn('Xhello world',out)

    def test_foreign_group_is_rejected_without_lifecycle_changes(self):
        foreign=self.proj/'foreign.txt'
        foreign.write_text('foreign\n')
        body=self.edit([('#1',0,[(1,1,1,1,'X')]),(foreign.as_posix(),'-',[(1,1,1,1,'Y')])])
        out=self.run_editor(['cmd echo.toast','wait-ext echo running','wait 100',
            'cmd command_palette','print-state','apply-document 1 '+body,
            'print-state','wait 100','print-doc','print-tabs'])
        states=self.states(out)
        self.assertEqual(states[0],states[1],out)
        self.assertIn('hello world',out)
        self.assertNotIn('Xhello world',out)
        self.assertEqual(foreign.read_text(),'foreign\n')
        self.assertFalse(any('foreign.txt' in line for line in self.echo_log()),self.echo_log())

    def test_unknown_restricted_document_does_not_disable_restriction(self):
        out=self.run_editor(['apply-document 0 '+self.edit(),'print-doc'])
        self.assertIn('hello world',out)
        self.assertNotIn('Xhello world',out)

    def test_format_on_save_cold_starts_and_writes_formatted_text(self):
        out=self.run_editor(['type y','cmd save','wait 700','print-state','print-doc'],exts=self.formatter())
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertIn(' dirty=0 ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),1)

    def test_delayed_save_does_not_write_before_formatting(self):
        # First process cancels while the formatter is waiting, so disk remains untouched.
        out=self.run_editor(['type y','cmd save','wait 150','cmd cancel_save','wait 700','print-state'],
            exts=self.formatter(delay=.5))
        self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')
        self.assertIn(' dirty=1 ',self.states(out)[0])
        self.assertIn('0 cancel ',self.requests())

    def test_timeout_saves_current_buffer_and_ignores_late_reply(self):
        out=self.run_editor(['type y','cmd save','wait 1000','print-state','print-doc','print-toast'],
            exts=self.formatter(delay=.7,timeout=250))
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn(' dirty=0 ',self.states(out)[0])
        self.assertIn('toast=Saved. Formatting timed out',out)

    def test_typing_during_formatting_saves_latest_text(self):
        # the formatter starts with the editor and has time to: started by the save itself, a slow start
        # under load sent the request after z was typed, and the formatted yz was right too
        out=self.run_editor(['wait 1500','type y','cmd save','wait 100','type z','wait 800','print-state','print-doc'],
            exts=self.formatter(delay=.5,on='startup'))
        self.assertEqual((self.proj/'a.txt').read_text(),'yzhello world\nsecond line\n')
        self.assertIn(' dirty=0 ',self.states(out)[0])

    def test_bypass_coalesces_pending_save_and_writes_unformatted(self):
        out=self.run_editor(['type y','cmd save','wait 100','cmd save_without_formatting',
            'wait 800','print-state','print-doc'],exts=self.formatter(delay=.5))
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn(' dirty=0 ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),1)

    def test_duplicate_save_writes_and_formats_once(self):
        self.run_editor(['type y','cmd save','wait 100','cmd save','wait 800'],exts=self.formatter(delay=.5))
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual(self.requests().count(' format '),1)

    def test_foreign_formatter_edit_does_not_open_or_change_files(self):
        foreign=self.proj/'foreign.txt'
        foreign.write_text('foreign\n')
        out=self.run_editor(['type y','cmd save','wait 700','print-tabs','print-toast'],exts=self.formatter(mode='foreign'))
        self.assertEqual(foreign.read_text(),'foreign\n')
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn('tabs=*a.txt',out)
        self.assertIn('toast=Saved. Formatting failed',out)

    def test_ambiguous_formatter_saves_without_chooser(self):
        out=self.run_editor(['type y','cmd save','wait 500','print-palette','print-toast'],
            exts=self.formatter(owners=('alice','bob')))
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn('toast=Saved. Choose an available default formatter',out)
        self.assertNotIn(' format ',self.requests())
        self.assertNotIn(' format ',self.requests('bob'))

    def test_save_before_close_waits_for_formatter(self):
        out=self.run_editor(['type y','cmd close_tab','key Return','print-state',
            'wait 900','print-state'],exts=self.formatter(delay=.5))
        states=self.states(out)
        self.assertIn('tabs=1 ',states[0])
        self.assertIn(' dirty=1 ',states[0])
        self.assertIn('tabs=0 ',states[1])
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')

    def test_cancelled_close_save_keeps_dirty_document_open(self):
        out=self.run_editor(['type y','cmd close_tab','key Return','wait 100','key Escape',
            'wait 900','print-state'],exts=self.formatter(delay=.5))
        self.assertIn('tabs=1 ',self.states(out)[0])
        self.assertIn(' dirty=1 ',self.states(out)[0])
        self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')

    def test_save_then_close_coalesces_one_formatter_request(self):
        out=self.run_editor(['type y','cmd save','wait 100','cmd close_tab','key Return',
            'wait 900','print-state'],exts=self.formatter(delay=.5))
        self.assertIn('tabs=0 ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),1)
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')

    def test_two_close_intents_complete_once(self):
        out=self.run_editor(['type y','cmd close_tab','key Return','wait 100','cmd close_tab',
            'key Return','wait 900','print-state'],exts=self.formatter(delay=.5))
        self.assertIn('tabs=0 ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),1)

    def test_background_save_preserves_active_tab_and_terminal(self):
        out=self.run_editor(['type y','cmd save','wait 100','open '+str(self.proj/'b.go'),
            'cmd toggle_terminal','print-state','wait 900','print-state'],
            exts=self.formatter(delay=.5))
        states=self.states(out)
        self.assertEqual(states[0],states[1],out)
        self.assertIn('active=b.go',states[1])
        self.assertIn('focus=8 ',states[1])
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')

    def test_new_close_dialog_supersedes_old_pending_close(self):
        out=self.run_editor(['type y','cmd close_tab','key Return','wait 100',
            'open '+str(self.proj/'b.go'),'type z','cmd close_tab','wait 900','print-state'],
            exts=self.formatter(delay=.5))
        state=self.states(out)[0]
        self.assertIn('tabs=2 ',state)
        self.assertIn('active=b.go ',state)
        self.assertIn('focus=5 ',state)
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'package b\n')

    def test_save_all_serializes_documents(self):
        out=self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z',
            'cmd save_all','wait 1500','print-state'],exts=self.formatter(delay=.4))
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'Xzpackage b\n')
        self.assertIn('active=b.go ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),2)

    def test_save_as_cancels_old_destination_and_formats_new_path(self):
        copy=self.proj/'copy.go'
        out=self.run_editor(['type y','cmd save','wait 100','cmd save_as','key ctrl+a',
            'type '+str(copy),'key Return','wait 1400','print-state'],exts=self.formatter(delay=.4))
        self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')
        self.assertEqual(copy.read_text(),'Xyhello world\nsecond line\n')
        self.assertIn('active=copy.go ',self.states(out)[0])
        self.assertIn('lang=Go ',self.states(out)[0])

    def test_readonly_authorization_is_retained_until_actual_write(self):
        path=self.proj/'a.txt'
        os.chmod(path,0o444)
        try:
            out=self.run_editor(['type y','cmd save','key Return','wait 900','print-state'],
                exts=self.formatter(delay=.4))
            self.assertEqual(path.read_text(),'Xyhello world\nsecond line\n')
            self.assertIn(' dirty=0 ',self.states(out)[0])
            self.assertFalse(os.access(path,os.W_OK))
        finally:
            os.chmod(path,0o644)

    def test_untitled_vim_write_quit_saves_then_closes(self):
        copy=self.proj/'copy.go'
        out=self.run_editor(['cmd new_file','cmd toggle_vim','type iy','key Escape',
            'type :wq','key Return','key ctrl+a','type '+str(copy),'key Return',
            'wait 1000','print-state'],exts=self.formatter(delay=.4),files=())
        self.assertEqual(copy.read_text(),'Xy\n')
        self.assertIn('tabs=0 ',self.states(out)[0])

    def test_discard_pending_document_ignores_late_formatter(self):
        out=self.run_editor(['type y','cmd save','wait 100','cmd toggle_vim','type :q!','key Return',
            'wait 1000','print-state'],exts=self.formatter(delay=.4))
        self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')
        self.assertIn('tabs=0 ',self.states(out)[0])

    def test_vim_write_all_then_quit_waits_for_each_save(self):
        self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z',
            'cmd toggle_vim','type :wqa','key Return','wait 1500'],exts=self.formatter(delay=.3))
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'Xzpackage b\n')
        self.assertEqual(self.requests().count(' format '),2)

    def test_cancelled_save_all_stops_before_second_document(self):
        out=self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z','cmd prev_tab',
            'cmd save_all','wait 100','cmd cancel_save','wait 1000','print-state'],
            exts=self.formatter(delay=.4))
        self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'package b\n')
        self.assertEqual(self.requests().count(' format '),1)

    def test_write_failure_keeps_document_open_after_close_save(self):
        root=self.formatter()
        os.chmod(self.proj,0o555)
        try:
            out=self.run_editor(['type y','cmd close_tab','key Return','wait 600','print-state','print-toast'],exts=root)
            self.assertIn('tabs=1 ',self.states(out)[0])
            self.assertIn(' dirty=1 ',self.states(out)[0])
            self.assertIn('toast=Could not save the file',out)
            self.assertEqual((self.proj/'a.txt').read_text(),'hello world\nsecond line\n')
        finally:
            os.chmod(self.proj,0o755)

    def test_formatter_error_falls_back_to_current_text(self):
        out=self.run_editor(['type y','cmd save','wait 600','print-state','print-toast'],
            exts=self.formatter(mode='error'))
        self.assertIn(' dirty=0 ',self.states(out)[0])
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn('toast=Saved. Formatting failed',out)

    def test_missing_default_does_not_fall_back(self):
        root=self.formatter()
        (self.work/'config/rhun/extensions.ini').write_text('[providers]\nformat.* = absent/format\n')
        out=self.run_editor(['type y','cmd save','wait 600','print-toast'],exts=root)
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertNotIn(' format ',self.requests())
        self.assertIn('toast=Saved. Choose an available default formatter',out)

    def test_stopped_default_is_not_restarted(self):
        root=self.formatter()
        (self.work/'config/rhun/extensions.ini').write_text('[providers]\nformat.* = alice/format\n')
        out=self.run_editor(['wait 300','ext-set alice/format stop','wait 300','type y',
            'cmd save','wait 600','print-toast','print-extensions'],exts=root)
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertNotIn(' format ',self.requests())
        self.assertIn('toast=Saved. Choose an available default formatter',out)

    def test_no_provider_still_saves_quietly(self):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text()+'\n[files]\nformat_on_save = true\n')
        out=self.run_editor(['type y','cmd save','wait 100','print-toast'])
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertIn('toast=Saved',out)

    def test_untitled_bypass_does_not_format_after_save_as(self):
        copy=self.proj/'copy.go'
        out=self.run_editor(['cmd new_file','type y','cmd save_without_formatting',
            'key ctrl+a','type '+str(copy),'key Return','wait 600','print-state'],
            exts=self.formatter(),files=())
        self.assertEqual(copy.read_text(),'y\n')
        self.assertNotIn(' format ',self.requests())

    def test_ordinary_save_does_not_supersede_pending_close(self):
        out=self.run_editor(['type y','cmd close_tab','key Return','wait 100','cmd save',
            'wait 900','print-state'],exts=self.formatter(delay=.4))
        self.assertIn('tabs=0 ',self.states(out)[0])
        self.assertEqual(self.requests().count(' format '),1)

    def test_replaced_save_all_continuations_do_not_duplicate_later_saves(self):
        out=self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z','cmd save_all',
            'wait 100','cmd save_all','wait 1500','print-state'],exts=self.formatter(delay=.3))
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'Xzpackage b\n')
        self.assertEqual(self.requests().count(' format '),2)

    def test_close_supersedes_save_all_before_next_document(self):
        out=self.run_editor(['type y','open '+str(self.proj/'b.go'),'type z','cmd prev_tab',
            'cmd save_all','wait 100','cmd close_tab','key Return','wait 1200','print-state'],
            exts=self.formatter(delay=.4))
        self.assertIn('tabs=1 ',self.states(out)[0])
        self.assertIn('active=b.go ',self.states(out)[0])
        self.assertEqual((self.proj/'a.txt').read_text(),'Xyhello world\nsecond line\n')
        self.assertEqual((self.proj/'b.go').read_text(),'package b\n')
        self.assertEqual(self.requests().count(' format '),1)

    def test_pending_close_resolves_new_tab_index(self):
        out=self.run_editor(['open '+str(self.proj/'b.go'),'type z','cmd close_tab','key Return',
            'wait 100','cmd prev_tab','cmd toggle_vim','type :q!','key Return',
            'wait 1000','print-state'],exts=self.formatter(delay=.4))
        self.assertIn('tabs=0 ',self.states(out)[0])
        self.assertEqual((self.proj/'b.go').read_text(),'Xzpackage b\n')

    def test_cancelled_quit_save_as_saves_updated_session(self):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text().replace('restore_session = false','restore_session = true'))
        self.run_editor(['cmd new_file','type y','cmd quit','key Return','key Escape',
            'open '+str(self.proj/'b.go')])
        sessions=[p for p in (self.work/'state/rhun').rglob('*') if p.is_file()]
        text=b''.join(p.read_bytes() for p in sessions)
        self.assertIn(b'b.go',text,sessions)

    def test_replacing_quit_save_as_saves_updated_session(self):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text().replace('restore_session = false','restore_session = true'))
        self.run_editor(['cmd new_file','type y','cmd quit','key Return','cmd command_palette',
            'key Escape','open '+str(self.proj/'b.go')])
        sessions=[p for p in (self.work/'state/rhun').rglob('*') if p.is_file()]
        self.assertIn(b'b.go',b''.join(p.read_bytes() for p in sessions),sessions)

    def test_cancelled_quit_save_as_readonly_confirmation_saves_session(self):
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text().replace('restore_session = false','restore_session = true'))
        path=self.proj/'a.txt'
        os.chmod(path,0o444)
        try:
            self.run_editor(['cmd new_file','type y','cmd quit','key Return','key ctrl+a',
                'type '+str(path),'key Return','key Escape','open '+str(self.proj/'b.go')])
            sessions=[p for p in (self.work/'state/rhun').rglob('*') if p.is_file()]
            self.assertIn(b'b.go',b''.join(p.read_bytes() for p in sessions),sessions)
        finally:
            os.chmod(path,0o644)



    def test_empty_format_reply_saves_without_failure_warning(self):
        out=self.run_editor(['type y','cmd save','wait 500','print-toast','print-state'],exts=self.formatter(mode='empty'))
        self.assertEqual((self.proj/'a.txt').read_text(),'yhello world\nsecond line\n')
        self.assertFalse(any('failed' in line.lower() for line in out),out)
        self.assertIn(' dirty=0 ',self.states(out)[0])

for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Saves,name,None)

if __name__=='__main__':
    unittest.main()
