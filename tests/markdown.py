#!/usr/bin/env python3
"""Markdown documents (markdown.s): blocks, inline styles, links and the layout, through the
headless print-md WIDTH PATH (md_dump's lines)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from viewsharness import ViewsBase  # noqa: E402

SAMPLE = """# Heading one

Some *emphasis*, **strong**, ~~struck~~ and `code` with a [link](https://example.com "title")
and a bare https://rhun.app/docs. Escaped \\*stars\\* and &amp; &lt;tag&gt; &#x2192;.
A hard break here
then the next line.

## Lists

- first item
- second with **bold**
  - nested one
  - nested two
- [ ] a task
- [x] a done task

1. one
2. two

> A quote with a [ref link][r1].
> > nested quote

---

```rust
fn main() {
    let x = "string";
}
```

| Name | Size | Kind |
|:-----|-----:|:----:|
| main.rs | 120 | file |
| `lib` | 3 | dir |

Setext heading
--------------

<!-- hidden comment -->
[r1]: https://example.org/ref
Final <https://auto.link> paragraph.
"""


class Markdown(ViewsBase):
    def dump(self, text, width=500):
        path = self.work / 'doc.md'
        path.write_text(text, encoding='utf-8')
        return self.run_editor([f'print-md {width} {path}'], exts=None, start=False)

    def blocks(self, out):
        return [l.split(' ', 2)[2] for l in out if l.startswith('block ')]

    def texts(self, out):
        return [l for l in out if l.startswith('item text ')]

    def field(self, line, name):
        return line.split(f' {name}=')[1].split(' ')[0]

    def test_blocks_and_their_context(self):
        b = self.blocks(self.dump(SAMPLE))
        kinds = [x.split(' ')[0] for x in b]
        self.assertEqual(kinds, ['type=head', 'type=para', 'type=head'] + ['type=para'] * 10 +
                         ['type=rule', 'type=code', 'type=row', 'type=row', 'type=row', 'type=head', 'type=para'])
        self.assertIn('level=1', b[0])
        self.assertTrue(b[3].startswith('type=para level=0 quote=0 list=1 marker=1'), b[3])
        self.assertTrue(b[5].startswith('type=para level=0 quote=0 list=2 marker=1'), b[5])     # nested
        self.assertIn('marker=3', b[7])                                     # a task
        self.assertIn('marker=4', b[8])                                     # a done task
        self.assertIn('marker=2 num=1', b[9])
        self.assertIn('marker=2 num=2', b[10])
        self.assertIn('quote=1', b[11])
        self.assertIn('quote=2', b[12])
        self.assertIn('level=2', b[18])                                     # setext ---

    def test_inline_styles(self):
        t = self.texts(self.dump(SAMPLE))
        by = {}
        for l in t:
            by.setdefault(self_text(l), l)                                  # the first of each
        self.assertEqual(self.field(by['emphasis'], 'style'), '2')
        self.assertEqual(self.field(by['strong'], 'style'), '1')
        self.assertEqual(self.field(by['struck'], 'style'), '8')
        self.assertEqual(self.field(by['code'], 'style'), '4')
        self.assertEqual(self.field(by['code'], 'face'), '4')
        self.assertEqual(self.field(by['link'], 'style'), '16')
        self.assertEqual(self.field(by['link'], 'link'), '0')
        self.assertIn('*stars*', by)                                        # escapes
        self.assertIn('&', by)
        self.assertIn('<tag>', by)
        self.assertIn('→.', by)                                        # &#x2192;
        self.assertEqual(self.field(by['https://rhun.app/docs'], 'link'), '1')
        self.assertEqual(self.field(by['ref'], 'link'), '2')                # defined after its use
        self.assertEqual(self.field(by['https://auto.link'], 'link'), '3')
        self.assertNotEqual(self.field(by['here'], 'y'), self.field(by['then'], 'y'))   # a hard break

    def test_links(self):
        out = self.dump(SAMPLE)
        links = [l for l in out if l.startswith('link ')]
        self.assertEqual(links, ['link 0 https://example.com', 'link 1 https://rhun.app/docs',
                                 'link 2 https://example.org/ref', 'link 3 https://auto.link'])

    def test_code_is_colored_by_its_grammar(self):
        t = self.texts(self.dump(SAMPLE))
        fn = [l for l in t if self_text(l) == 'fn'][0]
        self.assertEqual(self.field(fn, 'face'), '4')
        self.assertNotEqual(self.field(fn, 'color'), '1')                   # a syntax color, not fg

    def test_wrapping_follows_the_width(self):
        text = 'word ' * 60
        wide = self.dump(text, 800)
        narrow = self.dump(text, 200)
        hw = int(wide[0].split(' height=')[1].split(' ')[0])
        hn = int(narrow[0].split(' height=')[1].split(' ')[0])
        self.assertGreater(hn, hw)
        self.assertLessEqual(int(narrow[0].split(' maxw=')[1]), 200)

    def test_a_word_wider_than_the_line_is_cut(self):
        out = self.dump('x' * 300, 100)
        t = self.texts(out)
        self.assertGreater(len(t), 1)
        self.assertTrue(all(int(self.field(l, 'w')) <= 100 for l in t))

    def test_emphasis_needs_a_closer_and_underscores_inside_words_stay(self):
        t = self.texts(self.dump('a *lone star and snake_case_name and **unclosed\n'))
        self.assertEqual([self_text(l) for l in t], ['a', '*lone', 'star', 'and', 'snake_case_name', 'and',
                                                    '**unclosed'])
        self.assertTrue(all(self.field(l, 'style') == '0' for l in t))


def self_text(line):
    return line.split(' text=', 1)[1]


if __name__ == '__main__':
    unittest.main()
