#!/usr/bin/env python3
"""Provider choices, cold activation and delayed editor actions."""
import json
import unittest

host = __import__('ext-host')
PROGRAM = '''import os, sys, time
from pathlib import Path
log = Path(os.environ['RHUN_STATE']) / 'providers.log'
time.sleep(DELAY)
print(HELLO, flush=True)
for line in sys.stdin:
    with log.open('a') as f:
        f.write(line)
    words = line.split()
    if len(words) > 1 and words[1] in ('format', 'rename', 'symbols', 'signature'):
        body = '0\\n'
        if words[1] == 'signature':
            body = '0 0\\n' + os.environ['RHUN_EXTENSION'] + '(x)\\nhelp'
        print('ok ' + words[0] + ' ' + str(len(body)), flush=True)
        sys.stdout.write(body)
        sys.stdout.flush()
    if line.startswith('0 bye'):
        break
'''


class Providers(host.Host):
    def extensions(self, owners=('alice', 'bob'), delay=0, hello='hello 1 format rename symbols', pattern='*', signature=False):
        root = self.work / 'providers'
        for owner in owners:
            folder = root / owner / 'demo'
            folder.mkdir(parents=True)
            (folder / 'extension.ini').write_text(
                f'name = demo\nowner = {owner}\ntitle = Demo\nversion = 1\nprotocol = 1\n'
                'runtime = python3\nrun = main.py\non = command\n[needs]\ndocuments = write\n'
                f'[provides]\nformat = {pattern}\nrename = {pattern}\nsymbols = {pattern}\n')
            if signature:
                manifest = folder / 'extension.ini'
                manifest.write_text(manifest.read_text() + f'signature = {pattern}\nsignature.triggers = ( ,\n')
                hello += '' if 'signature' in hello else ' signature'
            (folder / 'main.py').write_text(f'DELAY = {delay!r}\nHELLO = {json.dumps(hello)}\n' + PROGRAM)
        return root

    def prefs(self, text):
        (self.work / 'config/rhun/extensions.ini').write_text('[providers]\n' + text)

    def requests(self, owner):
        p = self.work / f'state/rhun/extensions/{owner}--demo/providers.log'
        return ''.join(line for line in p.read_text().splitlines(keepends=True)
                       if len(line.split()) > 1 and line.split()[0] != '0'
                       and line.split()[1] in ('format', 'rename', 'symbols', 'signature')) if p.exists() else ''

    def test_ambiguous_action_opens_chooser_without_starting(self):
        out = self.run_editor(exts=self.extensions(), actions=[
            'cmd format_document', 'print-palette', 'print-extensions'])
        self.assertTrue(any('alice/demo' in x for x in out), out)
        self.assertTrue(any('bob/demo' in x for x in out), out)
        self.assertFalse(any('state=running' in x for x in out), out)

    def test_preference_cold_starts_only_selected_provider(self):
        self.prefs('format.* = bob/demo\n')
        self.run_editor(exts=self.extensions(), actions=['cmd format_document', 'wait 600', 'wait 300'])
        self.assertIn(' format ', self.requests('bob'))
        self.assertNotIn(' format ', self.requests('alice'))

    def test_missing_preference_never_falls_back(self):
        self.prefs('format.* = missing/demo\n')
        out = self.run_editor(exts=self.extensions(('alice',)), actions=[
            'cmd format_document', 'wait 300', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_sole_provider_cold_starts(self):
        self.run_editor(exts=self.extensions(('alice',)), actions=[
            'cmd format_document', 'wait 600', 'wait 300'])
        self.assertIn(' format ', self.requests('alice'))

    def test_disabled_preference_never_falls_back(self):
        self.prefs('format.* = bob/demo\n')
        out = self.run_editor(exts=self.extensions(), actions=[
            'ext-set bob/demo disabled 1', 'cmd format_document', 'wait 300', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_f2_handles_cold_rename_before_prompt(self):
        out = self.run_editor(exts=self.extensions(('alice',)), actions=[
            'key F2', 'wait 600', 'print-palette', 'key Return', 'wait 300'])
        self.assertTrue(any('prompt=New name' in x for x in out), out)
        self.assertIn(' rename ', self.requests('alice'))

    def test_f2_missing_preference_does_not_rename_file(self):
        self.prefs('rename.* = missing/demo\n')
        out = self.run_editor(exts=self.extensions(('alice',)), actions=[
            'key F2', 'print-palette', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertFalse(any('Rename File' in x for x in out), out)

    def test_changed_document_cancels_cold_action(self):
        self.run_editor(exts=self.extensions(('alice',), delay=.6), actions=[
            'cmd format_document', 'type x', 'wait 900', 'wait 300'])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_unnegotiated_feature_does_not_receive_request(self):
        out = self.run_editor(exts=self.extensions(('alice',), hello='hello 1'), actions=[
            'cmd format_document', 'wait 600', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_choice_remembers_owner_and_resumes_action(self):
        root = self.extensions()
        out = self.run_editor(exts=root, actions=[
            'cmd format_document', 'type bob/demo', 'key Return', 'wait 600', 'wait 300',
            'print-providers', 'print-palette'])
        self.assertIn(' format ', self.requests('bob'))
        self.assertNotIn(' format ', self.requests('alice'))
        self.assertTrue(any('format.- = bob/demo' in x for x in out), out)
        self.run_editor(exts=root, actions=['cmd format_document', 'wait 600', 'wait 300'])
        self.assertEqual(self.requests('bob').count(' format '), 2)

    def test_explicit_choice_saves_without_running_action(self):
        out = self.run_editor(exts=self.extensions(), actions=[
            'cmd select_default_formatter', 'type bob/demo', 'key Return', 'wait 300', 'print-providers'])
        self.assertIn('format.- = bob/demo', out)
        self.assertNotIn(' format ', self.requests('bob'))

    def test_cancelled_chooser_does_not_start_action(self):
        self.run_editor(exts=self.extensions(), actions=[
            'cmd format_document', 'key Escape', 'wait 300'])
        self.assertNotIn(' format ', self.requests('alice'))
        self.assertNotIn(' format ', self.requests('bob'))

    def test_automatic_clears_exact_preference_and_ends_action(self):
        self.prefs('format.* = alice/demo\nformat.- = bob/demo\n')
        out = self.run_editor(exts=self.extensions(), actions=[
            'cmd select_default_formatter', 'type Automatic', 'key Return', 'print-providers',
            'print-palette', 'wait 300'])
        self.assertIn('format.* = alice/demo', out)
        self.assertNotIn('format.- = bob/demo', out)
        self.assertEqual(out[-1], 'none')
        self.assertNotIn(' format ', self.requests('alice'))

    def test_exact_language_overrides_wildcard(self):
        self.prefs('format.* = alice/demo\nformat.Go = bob/demo\n')
        self.run_editor(exts=self.extensions(), files=('b.go',), actions=[
            'cmd format_document', 'wait 600', 'wait 300'])
        self.assertIn(' format ', self.requests('bob'))
        self.assertNotIn(' format ', self.requests('alice'))

    def test_stopped_preference_does_not_restart(self):
        self.prefs('format.* = bob/demo\n')
        out = self.run_editor(exts=self.extensions(), actions=[
            'wait 600', 'ext-set bob/demo stop', 'wait 500', 'cmd format_document', 'wait 300', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertNotIn(' format ', self.requests('alice'))
        self.assertNotIn(' format ', self.requests('bob'))

    def test_path_pattern_mismatch_does_not_fall_back(self):
        self.prefs('format.* = bob/demo\n')
        root = self.extensions(('alice',))
        folder = root / 'bob/demo'
        folder.mkdir(parents=True)
        (folder / 'extension.ini').write_text(
            'name = demo\nowner = bob\ntitle = Demo\nversion = 1\nprotocol = 1\n'
            'runtime = python3\nrun = main.py\non = command\n[provides]\nformat = *.go\n')
        (folder / 'main.py').write_text('DELAY=0\nHELLO="hello 1 format"\n' + PROGRAM)
        out = self.run_editor(exts=root, actions=['cmd format_document', 'wait 300', 'print-toast'])
        self.assertIn('Choose a provider', out[-1])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_tab_switch_cancels_cold_action(self):
        self.run_editor(exts=self.extensions(('alice',), delay=.6), actions=[
            'cmd format_document', 'open ' + str(self.proj / 'b.go'), 'wait 900', 'wait 300'])
        self.assertNotIn(' format ', self.requests('alice'))

    def test_other_palette_cancels_rename_prompt(self):
        self.run_editor(exts=self.extensions(('alice',)), actions=[
            'key F2', 'wait 600', 'cmd command_palette', 'key Escape', 'key Return', 'wait 300'])
        self.assertNotIn(' rename ', self.requests('alice'))

    def test_preference_write_failure_restores_old_choice(self):
        self.prefs('format.* = alice/demo\n')
        root = self.extensions()
        # A directory where the atomic settings writer needs a regular file makes the save fail.
        settings = self.work / 'config/rhun/extensions.ini'
        settings.unlink()
        settings.mkdir()
        out = self.run_editor(exts=root, actions=[
            'cmd select_default_formatter', 'type bob/demo', 'key Return', 'print-toast',
            'print-providers', 'wait 300'])
        self.assertTrue(any('Could not save provider' in x for x in out), out)
        self.assertFalse(any(' = bob/demo' in x for x in out), out)
        self.assertNotIn(' format ', self.requests('bob'))

    def test_new_provider_action_cancels_previous_language_query(self):
        root = self.extensions()
        folder = root / 'alice/demo'
        manifest = folder / 'extension.ini'
        manifest.write_text(manifest.read_text() + 'references = *\n')
        program = (folder / 'main.py').read_text().replace(
            'hello 1 format rename symbols', 'hello 1 format rename symbols references')
        program = program.replace("('format', 'rename', 'symbols', 'signature')", "('format', 'rename', 'symbols', 'signature', 'references')")
        program = program.replace("body = '0\\n'", "body = '0\\n'\n        if words[1] == 'references':\n            time.sleep(.4)\n            body = '1\\n1 1 1 2 2 5\\n#1hello'")
        (folder / 'main.py').write_text(program)
        out = self.run_editor(exts=root, actions=[
            'wait 600', 'cmd references', 'wait 100', 'cmd format_document', 'wait 800', 'print-palette'])
        self.assertIn('choose=Choose Formatter', out)
        self.assertNotIn('choose=Go to reference', out)
        raw = (self.work / 'state/rhun/extensions/alice--demo/providers.log').read_text()
        self.assertTrue(any(x.split()[0] != '0' and x.split()[1] == 'references'
                            for x in raw.splitlines() if len(x.split()) > 1), raw)

    def test_new_language_query_cancels_pending_cold_formatter(self):
        root = self.extensions(delay=.6)
        self.prefs('format.* = bob/demo\n')
        self.run_editor(exts=root, actions=[
            'cmd format_document', 'cmd references', 'wait 900', 'wait 300'])
        self.assertNotIn(' format ', self.requests('bob'))

    def test_explicit_signature_choice_resumes_and_persists(self):
        out = self.run_editor(exts=self.extensions(signature=True), actions=[
            'cmd signature_help', 'print-palette', 'type bob/demo', 'key Return',
            'wait 600', 'wait 300', 'print-providers'])
        self.assertIn('choose=Choose Signature Provider', out)
        self.assertIn('signature.- = bob/demo', out)
        self.assertIn(' signature ', self.requests('bob'))
        self.assertNotIn(' signature ', self.requests('alice'))

    def test_automatic_signature_is_quiet_when_ambiguous(self):
        out = self.run_editor(exts=self.extensions(signature=True), actions=[
            'wait 600', 'type (', 'wait 300', 'print-palette', 'print-toast'])
        self.assertEqual(out, ['none', 'toast='])
        self.assertNotIn(' signature ', self.requests('bob'))
        self.assertNotIn(' signature ', self.requests('alice'))

    def test_automatic_signature_uses_saved_provider(self):
        self.prefs('signature.* = bob/demo\n')
        self.run_editor(exts=self.extensions(signature=True), actions=[
            'wait 600', 'type (', 'wait 300'])
        self.assertIn(' signature ', self.requests('bob'))
        self.assertNotIn(' signature ', self.requests('alice'))

    def test_missing_automatic_signature_choice_is_quiet(self):
        self.prefs('signature.* = missing/demo\n')
        out = self.run_editor(exts=self.extensions(('alice',), signature=True), actions=[
            'wait 600', 'type (', 'wait 300', 'print-palette', 'print-toast'])
        self.assertEqual(out, ['none', 'toast='])
        self.assertNotIn(' signature ', self.requests('alice'))

    def test_signature_triggers_and_updates_stay_with_active_provider(self):
        self.prefs('signature.* = alice/demo\n')
        self.run_editor(exts=self.extensions(signature=True), actions=[
            'wait 600', 'type (', 'wait 300', 'provider-set signature * bob/demo',
            'type ,', 'wait 300', 'key Left', 'wait 300'])
        self.assertGreaterEqual(self.requests('alice').count(' signature '), 2)
        self.assertNotIn(' signature ', self.requests('bob'))

    def test_explicit_signature_replaces_active_session_with_new_default(self):
        self.prefs('signature.* = alice/demo\n')
        self.run_editor(exts=self.extensions(signature=True), actions=[
            'wait 600', 'type (', 'wait 300', 'provider-set signature * bob/demo',
            'cmd signature_help', 'wait 300'])
        self.assertIn(' signature ', self.requests('alice'))
        self.assertIn(' signature ', self.requests('bob'))

    def test_signature_cold_invocation_cancelled_by_edit(self):
        self.run_editor(exts=self.extensions(('alice',), signature=True, delay=.6), actions=[
            'cmd signature_help', 'type x', 'wait 900', 'wait 300'])
        self.assertNotIn(' signature ', self.requests('alice'))

    def test_shortcut_replaces_existing_provider_chooser(self):
        out = self.run_editor(exts=self.extensions(), actions=[
            'cmd format_document', 'key ctrl+r', 'print-palette', 'type bob/demo',
            'key Return', 'wait 600', 'wait 300', 'print-providers'])
        self.assertIn('choose=Choose Symbol Provider', out)
        self.assertIn('symbols.- = bob/demo', out)
        self.assertIn(' symbols ', self.requests('bob'))
        self.assertNotIn(' format ', self.requests('bob'))

    def escape_cold_action(self, command):
        out = self.run_editor(exts=self.extensions(('alice',), delay=.6, signature=True), actions=[
            'cmd ' + command, 'key Escape', 'wait 900', 'wait 300', 'print-palette'])
        self.assertEqual(out, ['none'])
        self.assertEqual(self.requests('alice'), '')

    def test_escape_cancels_cold_format(self):
        self.escape_cold_action('format_document')

    def test_escape_cancels_cold_rename(self):
        self.escape_cold_action('rename_file')

    def test_escape_cancels_cold_signature(self):
        self.escape_cold_action('signature_help')

    def test_focus_change_cancels_cold_rename_before_prompt(self):
        out = self.run_editor(exts=self.extensions(('alice',), delay=.6), actions=[
            'key F2', 'cmd toggle_terminal', 'wait 900', 'wait 300', 'print-palette'])
        self.assertEqual(out, ['none'])
        self.assertNotIn(' rename ', self.requests('alice'))

    def test_leaving_rename_prompt_preserves_new_terminal_focus(self):
        out = self.run_editor(exts=self.extensions(('alice',)), actions=[
            'key F2', 'wait 600', 'cmd toggle_terminal', 'wait 300', 'print-palette', 'print-state'])
        self.assertEqual(out[0], 'none')
        self.assertIn(' focus=8 ', out[-1])
        self.assertNotIn(' rename ', self.requests('alice'))

    def test_control_preferences_persist_and_clear(self):
        root = self.extensions()
        out = self.run_editor(exts=root, actions=[
            'provider-set format Go bob/demo', 'provider-set rename * alice/demo', 'print-providers'])
        self.assertIn('format.Go = bob/demo', out)
        out = self.run_editor(exts=root, actions=[
            'print-providers', 'provider-set format Go -', 'print-providers'])
        self.assertEqual(out.count('format.Go = bob/demo'), 1)
        self.assertEqual(out.count('rename.* = alice/demo'), 2)

    def test_malformed_preference_is_ignored(self):
        self.prefs('format.* = demo\nunknown.* = bob/demo\nformat. = bob/demo\n')
        out = self.run_editor(exts=self.extensions(('alice',)), actions=[
            'cmd format_document', 'wait 600', 'print-providers'])
        self.assertIn(' format ', self.requests('alice'))
        self.assertFalse(any(' = ' in x for x in out), out)


for name in dir(host.Host):
    if name.startswith('test_'):
        setattr(Providers, name, None)

if __name__ == '__main__':
    unittest.main()
