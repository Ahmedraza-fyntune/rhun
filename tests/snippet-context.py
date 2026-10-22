#!/usr/bin/env python3
"""Versioned read-only snippet context, raw framing and native permission guards."""
import base64
import json
import subprocess
import unittest

host=__import__('ext-host')
PEER=r'''
import base64,json,os,sys
from pathlib import Path
log=open(Path(os.environ['RHUN_STATE'])/'context.jsonl','w',buffering=1)
versions={}
def send(header,body=b''):
    sys.stdout.buffer.write(header.encode()+b'\n'+body);sys.stdout.buffer.flush()
send(HELLO)
while True:
    line=sys.stdin.buffer.readline()
    if not line:break
    words=line.decode().split();body=b''
    if words[:2]==['0','edits']:
        body=sys.stdin.buffer.read(int(words[4]));versions[words[2]]=int(words[3])
    elif words[:2] in (['0','opened'],['0','resync']):versions[words[2]]=int(words[3])
    elif words and words[0]=='ok' and words[1] in ('20','22','24'):
        body=sys.stdin.buffer.read(int(words[-1]))
    log.write(json.dumps({'line':line.decode().strip(),'body':base64.b64encode(body).decode()})+'\n')
    if words[:2]==['0','bye']:break
    if words[:2]==['0','run']:
        doc=min(versions,key=int) if INACTIVE and versions else words[3]
        version=versions.get(doc,0)
        for text,data in REQUESTS:
            send(text.format(doc=doc,version=version),data)
'''


class SnippetContext(host.Host):
    def extension(self,requests=None,needs='read',features=True,inactive=False):
        folder=self.work/'extensions/alice/context'
        folder.mkdir(parents=True)
        (folder/'extension.ini').write_text(
            'name = context\nowner = alice\ntitle = Context\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\non = command\n[commands]\nprobe = Context\n'
            f'[needs]\ndocuments = {needs}\nproject = read\n'
            '[subscribe]\nopened = *\nedits = *\n')
        if requests is None:requests=[('20 snippet-context {doc} {version} 1 1 1 1',b'')]
        hello='hello 1'+(' snippets' if features else '')
        (folder/'main.py').write_text(f'HELLO={hello!r}\nINACTIVE={inactive!r}\nREQUESTS={requests!r}\n'+PEER)
        return self.work/'extensions'

    def run_context(self,requests=None,actions=(),**kwargs):
        root=self.extension(requests,**kwargs)
        return self.run_editor([*actions,'print-state','cmd context.probe','wait 350','print-state','print-doc'],exts=root)

    def trace(self):
        path=self.work/'state/rhun/extensions/alice--context/context.jsonl'
        return [dict(x,body=base64.b64decode(x['body'])) for x in map(json.loads,path.read_text().splitlines())]

    def context(self):
        reply=next(x for x in self.trace() if x['line'].startswith('ok 20 '))
        header,raw=reply['body'].split(b'\n',1);f=header.split()
        self.assertEqual(f[:2],[b'context',b'1']);self.assertEqual(len(f),13)
        nums=list(map(int,f[2:]));parts=[]
        for length in nums[5:]:parts.append(raw[:length]);raw=raw[length:]
        self.assertEqual(raw,b'');self.assertEqual(len(reply['body']),int(reply['line'].split()[-1]))
        return nums[:5],parts

    def test_unicode_multiline_range_is_literal_and_read_only(self):
        (self.proj/'a.txt').write_bytes('  😀hello\nnextline\n'.encode())
        out=self.run_context([('20 snippet-context {doc} {version} 1 3 2 5',b'')],actions=['key ctrl+End'])
        nums,parts=self.context()
        self.assertEqual(nums,[1,3,4,1,0])
        self.assertEqual(parts,['😀hello\nnext'.encode(),'  😀hello'.encode(),(self.proj/'a.txt').as_posix().encode(),self.proj.as_posix().encode(),b'  ',b''])
        states=[x for x in out if x.startswith('tabs=')]
        self.assertEqual(states[0],states[1]);self.assertIn('nextline',out)

    def test_nul_inserted_into_document_is_length_framed(self):
        # Disk files with NUL are intentionally rejected as binary; a document
        # edit can contain literal NUL and must still frame its context exactly.
        self.run_context([('21 replace {doc} {version} 1 1 1 1 1',b'\x00'),
            ('20 snippet-context {doc} 1 1 1 1 2',b'')],needs='write')
        self.assertEqual(self.context()[1][0],b'\x00')

    def test_mid_line_indent_stops_at_first_non_whitespace(self):
        (self.proj/'a.txt').write_text('\t x  y\n')
        self.run_context([('20 snippet-context {doc} {version} 1 7 1 7',b'')])
        nums,parts=self.context();self.assertEqual(nums[:2],[1,7]);self.assertEqual(parts[4],b'\t ')

    def test_indent_inside_leading_whitespace_is_clamped_to_start(self):
        (self.proj/'a.txt').write_text('    x\n')
        self.run_context([('20 snippet-context {doc} {version} 1 3 1 3',b'')])
        self.assertEqual(self.context()[1][4],b'  ')

    def test_crlf_option_overrides_and_grammar_comment_for_inactive_doc(self):
        (self.proj/'a.go').write_bytes(b'\tpackage a\r\n')
        root=self.extension([('30 option {doc} tab_width 8',b''),('31 option {doc} insert_spaces no',b''),
            ('20 snippet-context {doc} {version} 1 2 1 2',b'')],needs='write',inactive=True)
        self.run_editor(['cmd context.probe','wait 350','print-tabs','print-options'],exts=root,files=('a.go','b.go'))
        nums,parts=self.context();self.assertEqual(nums,[1,2,8,0,1]);self.assertEqual(parts[1],b'\tpackage a')
        self.assertEqual(parts[4:], [b'\t',b'//'])

    def test_untitled_document_context(self):
        self.run_context(actions=['cmd new_file','type abc'])
        nums,parts=self.context();self.assertEqual(parts[1],b'abc');self.assertEqual(parts[2],b'')

    def test_stale_and_unknown_document_are_errors(self):
        self.run_context([('20 snippet-context {doc} 9223372036854775807 1 1 1 1',b''),
            ('21 snippet-context 9223372036854775807 0 1 1 1 1',b'')])
        lines=[x['line'] for x in self.trace()]
        self.assertTrue(any(x.startswith('error 20 stale ') for x in lines),lines)
        self.assertTrue(any(x.startswith('error 21 nodoc ') for x in lines),lines)

    def test_bad_positions_and_utf8_split(self):
        (self.proj/'a.txt').write_text('😀\n', encoding='utf-8')
        self.run_context([('20 snippet-context {doc} {version} 1 2 1 2',b''),
            ('21 snippet-context {doc} {version} 2 1 1 1',b''),
            ('23 snippet-context {doc} {version} 99 1 99 1',b'')])
        lines=[x['line'] for x in self.trace()]
        for id in (20,21,23):self.assertTrue(any(x.startswith(f'error {id} badpos ') for x in lines),lines)

    def test_strict_decimal_and_exact_field_count(self):
        for span in ('1 1 1 1 extra','+1 1 1 1','9223372036854775808 1 1 1','1 -1 1 1'):
            with self.subTest(span=span):
                # One syntax rejection per fresh connection, below the three-strike limit.
                if (self.work/'extensions').exists():
                    import shutil;shutil.rmtree(self.work/'extensions')
                self.run_context([(f'20 snippet-context {{doc}} {{version}} {span}',b'')])
                self.assertTrue(any(x['line'].startswith('error 20 syntax ') for x in self.trace()),self.trace())

    def test_requires_feature_and_document_read(self):
        for kwargs,code in (({'features':False},'unknown'),({'needs':'none'},'needs')):
            with self.subTest(code=code):
                if (self.work/'extensions').exists():
                    import shutil;shutil.rmtree(self.work/'extensions')
                self.run_context(**kwargs)
                self.assertTrue(any(x['line'].startswith(f'error 20 {code} ') for x in self.trace()),self.trace())

    def test_large_returned_line_is_rejected_without_mutation(self):
        (self.proj/'a.txt').write_text('a'*(4<<20))
        out=self.run_context()
        self.assertTrue(any(x['line'].startswith('error 20 toobig ') for x in self.trace()),self.trace())
        states=[x for x in out if x.startswith('tabs=')];self.assertEqual(states[0],states[1])

    def test_nonreturned_large_document_does_not_prevent_small_context(self):
        (self.proj/'a.txt').write_text('short\n'+'a'*(4<<20))
        self.run_context();self.assertEqual(self.context()[1][1],b'short')

    def test_invalid_utf8_is_rejected(self):
        (self.proj/'a.txt').write_bytes(b'\xff\n')
        self.run_context()
        self.assertTrue(any(x['line'].startswith('error 20 refused ') for x in self.trace()),self.trace())

    def test_exact_four_mib_body_is_accepted_and_one_more_byte_refused(self):
        path=str(self.proj/'a.txt').encode();project=str(self.proj).encode()
        n=(4<<20)-len(path)-len(project)
        for _ in range(4):
            header=f'context 1 1 1 4 1 0 0 {n} {len(path)} {len(project)} 0 0\n'.encode()
            n=(4<<20)-len(header)-len(path)-len(project)
        (self.proj/'a.txt').write_bytes(b'a'*n)
        self.run_context();self.assertEqual(len(self.context()[1][1]),n)
        reply=next(x for x in self.trace() if x['line'].startswith('ok 20 '))
        self.assertEqual(len(reply['body']),4<<20)
        import shutil;shutil.rmtree(self.work/'extensions')
        (self.proj/'a.txt').write_bytes(b'a'*(n+1));self.run_context()
        self.assertTrue(any(x['line'].startswith('error 20 toobig ') for x in self.trace()),self.trace())

    def test_readonly_diff_context_is_allowed(self):
        def git(*args):
            subprocess.run(['git',*args],cwd=self.proj,check=True,capture_output=True)
        git('init','-q');git('add','a.txt')
        git('-c','user.name=t','-c','user.email=t@example.invalid','commit','-q','-m','one')
        (self.proj/'a.txt').write_text('changed\n')
        config=self.work/'config/rhun/config'
        config.write_text(config.read_text().replace('[git]\nenabled = false','[git]\nenabled = true'))
        self.run_context(actions=['wait-git','cmd git_changes','wait-git'])
        self.assertTrue(any(x['line'].startswith('ok 20 ') for x in self.trace()),self.trace())

    def test_same_pump_edit_events_precede_context_and_later_text(self):
        self.run_context([('21 replace {doc} {version} 1 1 1 1 1',b'X'),
            ('20 snippet-context {doc} 1 1 1 1 2',b''),('22 text {doc}',b'')],needs='write')
        trace=self.trace();query=next(i for i,x in enumerate(trace) if x['line'].startswith('ok 20 '))
        edits=[x for x in trace[:query] if x['line'].startswith('0 edits ')]
        self.assertEqual([x['body'] for x in edits],[b'0 0 1\nX'])
        self.assertEqual(self.context()[1][0],b'X')
        text=next(x for x in trace if x['line'].startswith('ok 22 '));self.assertTrue(text['body'].startswith(b'Xhello'))

    def test_large_edit_resync_precedes_context_and_is_not_repeated(self):
        self.run_context([('21 replace {doc} {version} 1 1 1 1 1048577',b'A'*1048577),
            ('20 snippet-context {doc} 1 1 1 1 1',b''),('22 text {doc}',b''),('24 text {doc}',b'')],needs='write')
        trace=self.trace();query=next(i for i,x in enumerate(trace) if x['line'].startswith('ok 20 '))
        resync=[i for i,x in enumerate(trace) if x['line'].startswith('0 resync ')]
        self.assertEqual(len(resync),1,trace);self.assertLess(resync[0],query)


for name in dir(host.Host):
    if name.startswith('test_'):setattr(SnippetContext,name,None)

if __name__=='__main__':unittest.main()
