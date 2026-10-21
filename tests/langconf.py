#!/usr/bin/env python3
"""Language configuration (docs/extensions/v1.1.md "Language configuration"): the keys a grammar
and an extension's [language.NAME] set, merged with the defaults (without any: the behaviour
before them), and what they do while typing: auto-closing and surrounding pairs (not inside
strings when asked), Enter indentation from token rules, auto-outdent of an untouched line,
continued lists and comments, doc comment blocks, Backspace in an empty pair, Toggle Comment with
a block pair, fold markers, the single-cursor and multi-cursor paths alike, one undo step."""
import unittest

contribhost = __import__('contribhost')
CONFIG = ('[ui]\nagents_panel = false\n[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
TOY = '''name = Toy
files = *.toy
comment = ;
block = <* *>
string = " \\
brackets = () [] <>
autoclose = ( ) [ ] < > " " {% %}
autoclose_code = "
surround = ( ) [ ] < >
indent_open = begin ^when ($
indent_close = finish )
indent_middle = otherwise
indent_dedent_after = leave
continue = ;;
doc_block = <* * *>
fold = indent
fold_markers = #region #endregion
'''


class LangConf(contribhost.Contrib):
    def setUp(self):
        super().setUp()
        (self.work / 'config/rhun/config').write_text(CONFIG, encoding='utf-8')

    def edit(self, name, text, actions, exts=None, extra=()):
        """The document after the actions (from the end of its text), and the other output lines."""
        (self.proj / name).write_text(text, encoding='utf-8')
        out = self.run_editor(exts=exts or (self.work / 'none'), files=(name,), drop_waits=True,
                              actions=['key ctrl+End', *actions, 'echo @doc', 'print-doc', *extra])
        i = out.index('@doc')
        j = out.index('<eod>', i)
        return '\n'.join(out[i + 1:j]), out[:i] + out[j + 1:]

    def user_grammar(self, text):
        folder = self.work / 'config/rhun/syntax'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'toy.syn').write_text(text, encoding='utf-8')

    # ---------------------------------------------------------------- defaults

    def test_defaults_keep_the_plain_behaviour(self):
        doc, _ = self.edit('a.txt', '', ['type f(', 'type x', 'type )', 'type ;', 'key Return', 'type {',
                                         'key Return', 'type y', 'key ctrl+End', 'key Return', 'type "a',
                                         'type "', 'key space', 'type [', 'key BackSpace', 'type it"s'])
        self.assertEqual(doc, 'f(x);\n{\n    y\n}\n"a" it"s')

    def test_a_mismatched_closer_stays_on_its_line(self):
        doc, _ = self.edit('a.txt', '{]', ['key Home', 'key Right', 'key Return'])
        self.assertEqual(doc, '{\n    ]')

    # ---------------------------------------------------------------- built-in configurations

    def test_lua_enter_outdent_pairs_and_strings(self):
        doc, _ = self.edit('m.lua', '', ['type if x then', 'key Return', 'type print("a', 'type (', 'key End',
                                         'key Return', 'type else', 'key Return', 'type y = {', 'key Return',
                                         'key Down', 'key End', 'key Return', 'type end', 'key Return'])
        self.assertEqual(doc, 'if x then\n    print("a(")\nelse\n    y = {\n        \n    }\nend\n')

    def test_python_colon_middle_and_dedent(self):
        doc, _ = self.edit('p.py', '', ['type def f(x):', 'key Return', 'type if x:', 'key Return',
                                        'type return 1', 'key Return', 'type else:', 'key Return', 'type pass',
                                        'key Return', 'type y'])
        self.assertEqual(doc, 'def f(x):\n    if x:\n        return 1\n    else:\n        pass\n    y')

    def test_outdent_leaves_a_hand_aligned_line(self):
        doc, _ = self.edit('p.py', 'if x:\n    a\n  ', ['type else:'])
        self.assertEqual(doc, 'if x:\n    a\n  else:')

    def test_markdown_lists_continue_and_end(self):
        doc, _ = self.edit('n.md', '- one', ['key Return', 'type two', 'key Return', 'key Return', 'type text'])
        self.assertEqual(doc, '- one\n- two\ntext')

    def test_doc_comment_blocks_and_line_comments(self):
        doc, _ = self.edit('c.c', '/***/', ['key Home', 'key Right', 'key Right', 'key Right', 'key Return',
                                            'type a', 'key Return', 'type b'])
        self.assertEqual(doc, '/**\n * a\n * b\n */')
        doc, _ = self.edit('r.rs', '/// x', ['key Return', 'type y'])
        self.assertEqual(doc, '/// x\n/// y')

    def test_toggle_comment_uses_the_block_pair_without_a_line_comment(self):
        doc, _ = self.edit('h.html', '<p>\n  hi\n</p>', ['key ctrl+a', 'cmd toggle_comment'])
        self.assertEqual(doc, '<!-- <p>\n  hi\n</p> -->')
        doc, _ = self.edit('h.html', '<!-- <p> -->', ['cmd toggle_comment'])
        self.assertEqual(doc, '<p>')

    # ---------------------------------------------------------------- a grammar with every key

    def test_a_grammar_with_every_key(self):
        self.user_grammar(TOY)
        doc, out = self.edit('t.toy', '', [
            'type begin', 'key Return', 'type x <', 'type "', 'key End', 'key Return', 'type finish', 'key Return',
            'type ;; note', 'key Return', 'type more', 'key Return', 'key Return', 'type "in {%'],
            extra=['print-langconf'])
        # (Enter on a line holding only the marker ends the list there; {% does not close before ")
        self.assertEqual(doc, 'begin\n    x <"">\nfinish\n;; note\n;; more\n"in {%"')
        doc, _ = self.edit('t.toy', '<* d', ['key Return', 'type e', 'key Return', 'type f'])
        self.assertEqual(doc, '<* d\n * e\n * f')
        self.assertIn('indent_open=begin ^when ($ source=user', out)
        self.assertIn('fold_markers=#region #endregion source=user', out)
        self.assertIn('brackets=() [] <> source=user', out)

    def test_qualifiers_middle_and_dedent_words(self):
        self.user_grammar(TOY)
        doc, _ = self.edit('t.toy', '', ['type a when b', 'key Return', 'type when c', 'key Return', 'type leave',
                                         'key Return', 'type f(', 'key End', 'key Return', 'type otherwise',
                                         'key space', 'type z'])
        # "when" opens only first on a line, "(" only last; "leave" takes a unit off the next line
        self.assertEqual(doc, 'a when b\nwhen c\n    leave\nf()\notherwise z')

    def test_surround_wraps_a_selection(self):
        self.user_grammar(TOY)
        doc, _ = self.edit('t.toy', 'word', ['key shift+Home', 'type <'])
        self.assertEqual(doc, '<word>')

    def test_backspace_deletes_a_multibyte_pair(self):
        self.user_grammar(TOY)
        doc, _ = self.edit('t.toy', '', ['type {%', 'key BackSpace', 'type x'])
        self.assertEqual(doc, 'x')

    # ---------------------------------------------------------------- extensions' [language.NAME]

    def lang_ext(self, owner, name, body):
        root = self.work / 'exts'
        self.make_ext(root, owner=owner, name=name, extra=body)
        return root

    def test_an_extension_overlay_and_conflicts(self):
        self.lang_ext('alice', 'demo', '[language.Lua]\ncontinue = --\nindent_middle = else elseif\nbogus = 1\n'
                                       '[language.Plain_Text]\ncontinue = >\n')
        root = self.lang_ext('bob', 'other', '[language.Lua]\ncontinue = ---\n')
        doc, out = self.edit('m.lua', '--- a', ['key Return', 'type b'], exts=root,
                             extra=['print-langconf', 'print-contrib-problems alice/demo',
                                    'print-contrib-problems bob/other', 'print-extensions'])
        # the first enabled extension in discovery order sets a key (print-extensions' order)
        order = [l.split()[0] for l in out if l.startswith(('alice/demo ', 'bob/other '))]
        first = order[0]
        self.assertIn('continue=%s source=ext:%s' % ('---' if first == 'bob/other' else '--', first), out)
        self.assertEqual(doc, '--- a\n--- b' if first == 'bob/other' else '--- a\nb')
        self.assertIn('indent_middle=else elseif source=ext:alice/demo', out)
        self.assertIn('indent_open=then do function repeat { ( [ source=grammar', out)
        self.assertIn('problem=[language.Lua] bogus: not a language key', out)
        self.assertIn('problem=[language.Lua] continue: also set by alice/demo', out)
        self.assertIn('problem=[language.Lua] continue: also set by bob/other', out)

    def test_a_user_grammar_wins_over_an_extension(self):
        self.user_grammar(TOY)
        root = self.lang_ext('alice', 'demo', '[language.Toy]\ncontinue = %%\nfold = brackets\n')
        _, out = self.edit('t.toy', '', [], exts=root, extra=['print-langconf'])
        self.assertIn('continue=;; source=user', out)
        self.assertIn('fold=indent source=user', out)
        self.user_grammar(TOY.replace('fold = indent\n', ''))
        _, out = self.edit('t.toy', '', [], exts=root, extra=['print-langconf'])
        self.assertIn('fold=brackets source=ext:alice/demo', out)

    def test_a_turned_off_extension_does_not_count(self):
        root = self.lang_ext('alice', 'demo', '[language.Lua]\ncontinue = --\n')
        _, out = self.edit('m.lua', '', ['ext-set demo disabled 1'], exts=root, extra=['print-langconf'])
        self.assertIn('continue=--- source=grammar', out)

    # ---------------------------------------------------------------- multi-cursor, undo, folding

    def carets(self, name, text, lines):
        """Actions putting a caret at the end of each listed line (the first one the primary)."""
        (self.proj / name).write_text(text, encoding='utf-8')
        out = self.run_editor(exts=self.work / 'none', files=(name,), drop_waits=True,
                              actions=['print-xy %d 1' % l for l in lines])
        acts = []
        for i, (l, xy) in enumerate(zip(lines, out)):
            x, y = map(int, xy.split())
            acts.append('click %d %d%s' % (x + 600, y, ' alt' if i else ''))
        return acts

    def test_multi_cursor_enter_and_outdent_equal_single(self):
        text = 'if a then\nif b then\n'
        acts = self.carets('m.lua', text, [1, 2])
        doc, _ = self.edit('m.lua', text, acts + ['key Return', 'type x', 'key Return', 'type end', 'key space'])
        self.assertEqual(doc, 'if a then\n    x\nend \nif b then\n    x\nend \n')

    def test_outdent_and_its_character_undo_as_one_step(self):
        doc, _ = self.edit('m.lua', 'if a then\n    x\n    end', ['key space', 'key ctrl+z'])
        self.assertEqual(doc, 'if a then\n    x\n    end')

    def test_fold_markers_make_a_range(self):
        text = 'a()\n//#region setup\nb()\nc()\n//#endregion\nd()\n'
        _, out = self.edit('j.js', text, ['key ctrl+Home', 'key Down', 'cmd fold'],
                           extra=['print-present folds'])
        self.assertEqual(out, ['fold 2-5', 'hidden 3'])     # START's line to END's, both included


if __name__ == '__main__':
    unittest.main()
