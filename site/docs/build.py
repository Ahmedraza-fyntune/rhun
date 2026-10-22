#!/usr/bin/env python3
"""Render the short website guides using only the Python standard library.

Guide metadata lives in pages.json; each guide body is an HTML fragment.
The built homepage supplies the shared navigation, icons, and footer so their
links, appearance controls, and icon license cannot drift between pages.
"""
import html
import json
from pathlib import Path
import re
import sys

SOURCE = Path(__file__).resolve().parent
out = Path(sys.argv[1])
version, asset_version = sys.argv[2:4]
pages = json.loads((SOURCE / 'pages.json').read_text())
home = (out / 'index.html').read_text()


def extract(pattern):
    matches = re.findall(pattern, home, re.S)
    if len(matches) != 1:
        raise ValueError(f'Expected one shared homepage fragment: {pattern}')
    return matches[0]


def root_links(fragment):
    return (fragment.replace('href="./"', 'href="/"')
            .replace('href="#install"', 'href="/#install"')
            .replace('src="favicon.svg', 'src="/favicon.svg')
            .replace('href="fonts/', 'href="/fonts/'))


icons = extract(r'<!-- GitHub and Discord icons:.*?</svg>')
header = root_links(extract(r'<header class="top">.*?</header>'))
header = header.replace('href="/docs/"', 'href="/docs/" aria-current="true"')
footer = root_links(extract(r'<footer>.*?</footer>'))
esc = html.escape


def guide_nav(current=None):
    return '<nav class="guide-nav" aria-label="Guides"><a class="all-guides" href="/docs/">← All guides</a>' + ''.join(
        f'<a href="/docs/{p["slug"]}/"' + (' aria-current="page"' if p['slug'] == current else '') +
        f'>{p["title"]}</a>' for p in pages) + '</nav>'


def image(page, eager=False):
    return f'''<figure class="doc-screen"><img src="/img/{page['image']}-800.webp"
      srcset="/img/{page['image']}-800.webp 800w, /img/{page['image']}.webp 1600w"
      sizes="(max-width: 760px) calc(100vw - 40px), (max-width: 1100px) 65vw, 700px"
      width="1600" height="1000" alt="{esc(page['alt'])}" loading="{'eager' if eager else 'lazy'}" decoding="async"></figure>'''


def document(title, description, path, body, kind):
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} | rhun docs</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="https://rhun.app{path}">
<meta name="theme-color" content="#111216">
<meta name="color-scheme" content="light dark">
<script src="/theme.js?v={asset_version}"></script>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/fonts/InstrumentSans-Latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/style.css?v={asset_version}">
<link rel="stylesheet" href="/docs/docs.css?v={asset_version}">
<script src="/docs/docs.js?v={asset_version}" defer></script>
<meta property="og:type" content="website">
<meta property="og:site_name" content="rhun">
<meta property="og:title" content="{esc(title)} | rhun docs">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="https://rhun.app{path}">
<meta property="og:image" content="https://rhun.app/img/card.png">
<meta name="twitter:card" content="summary_large_image">
</head>
<body class="docs {kind}">
{icons}
<a class="skip" href="#main">Skip to content</a>
{header}
{body}
{footer}
</body>
</html>
'''


landing_rail = '<nav class="category-rail" aria-label="Explore the guides"><div class="rail-links">' + ''.join(
    f'<a href="#{p["slug"]}" data-track="{p["slug"]}"><span class="rail-title">{p["title"]}</span></a>'
    for i, p in enumerate(pages, 1)) + '</div><div class="rail-meter" aria-hidden="true"><span></span></div></nav>'
chapters = ''
for i, p in enumerate(pages, 1):
    links = ''.join(f'<a href="/docs/{p["slug"]}/#{sid}">{title}</a>' for sid, title in p['sections'][:3])
    chapters += f'''<section class="doc-chapter" id="{p['slug']}" aria-labelledby="{p['slug']}-title">
      <h2 id="{p['slug']}-title"><a href="/docs/{p['slug']}/">{p['title']}</a></h2>
      <p class="chapter-description">{p['description']}</p>
      <a class="chapter-image-link" href="/docs/{p['slug']}/" aria-label="Read the {p['title'].lower()} guide">{image(p, i == 1)}</a>
      <div class="chapter-bottom"><a class="button" href="/docs/{p['slug']}/">Read the guide</a></div>
      <div class="chapter-topics">{links}</div>
    </section>'''
landing = f'''<main id="main" class="wrap">
  <section class="docs-intro" aria-labelledby="docs-title">
    <div><h1 id="docs-title">Get to know<br><span>your editor.</span></h1></div>
    <div class="intro-aside"><p>Short guides for the things you do every day. From your first file to your next commit.</p>
    <a href="/docs/getting-started/" class="text-link">Start with the basics</a>
    </div>
  </section>
  <div class="docs-explore">{landing_rail}<div class="doc-chapters">{chapters}</div></div>
  <section class="docs-help"><h2>Need a hand?</h2><div><a class="button" href="https://discord.gg/Aj4drpFbWf">Ask on Discord</a><a class="text-link" href="https://github.com/vshvedov/rhun/blob/main/docs/guide.md">Full technical reference</a></div></section>
</main>'''
(out / 'docs').mkdir(exist_ok=True)
(out / 'docs/index.html').write_text(document('Get to know your editor', 'Short guides to installing rhun, editing code, using the terminal, following agents, Git, and customization.', '/docs/', landing, 'docs-index'))

for i, page in enumerate(pages):
    slug = page['slug']
    content = (SOURCE / f'{slug}.html').read_text()
    for section_id, _ in page['sections']:
        if content.count(f'id="{section_id}"') != 1:
            raise ValueError(f'{slug}: expected section {section_id}')
    toc = '<nav class="page-toc" aria-label="On this page"><p class="toc-title">On this page</p>' + ''.join(
        f'<a href="#{sid}" data-track="{sid}">{title}</a>' for sid, title in page['sections']) + '</nav>'
    adjacent = ''
    for j, direction in [(i - 1, 'Previous'), (i + 1, 'Next')]:
        if 0 <= j < len(pages):
            p = pages[j]
            adjacent += f'<a href="/docs/{p["slug"]}/"><strong>{p["title"]} <span aria-hidden="true">{"←" if direction == "Previous" else "→"}</span></strong></a>'
        else:
            adjacent += '<a href="/docs/"><strong>All guides</strong></a>'
    body = f'''<main id="main" class="wrap guide-layout">
    <aside class="guide-sidebar">{guide_nav(slug)}</aside>
    <div class="guide-main">
      <header class="guide-heading"><h1>{page['title']}</h1><p>{page['description']}</p></header>
      {image(page, True)}
      <div class="mobile-toc">{toc.replace('aria-label="On this page"', 'aria-label="Page sections"').replace(' data-track=', ' data-mobile-track=')}</div>
      <article class="guide-content" aria-label="{page['title']}">{content}</article>
      <nav class="adjacent-guides" aria-label="Continue reading">{adjacent}</nav>
    </div><aside class="guide-toc">{toc}</aside>
    </main>'''
    target = out / 'docs' / slug
    target.mkdir(exist_ok=True)
    (target / 'index.html').write_text(document(page['title'], page['description'], f'/docs/{slug}/', body, 'docs-guide'))

# The extension protocol: docs/extensions/v1.md as a page, and as itself for agents.
def inline(text):
    """Markdown inline: `code`, **bold**, [text](url); everything else escaped."""
    out, i = [], 0
    for m in re.finditer(r'`([^`]+)`|\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)', text):
        out.append(esc(text[i:m.start()]))
        if m.group(1) is not None:
            out.append(f'<code>{esc(m.group(1))}</code>')
        elif m.group(2) is not None:
            out.append(f'<strong>{inline(m.group(2))}</strong>')
        else:
            out.append(f'<a href="{esc(m.group(4))}">{inline(m.group(3))}</a>')
        i = m.end()
    out.append(esc(text[i:]))
    return ''.join(out)


def slug_of(heading):
    return re.sub(r'[^a-z0-9]+', '-', heading.lower()).strip('-')


def markdown(md):
    """The subset the spec uses: headings, paragraphs, fenced code, tables, lists."""
    lines, out, toc, i = md.split('\n'), [], [], 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('```'):
            j = i + 1
            while j < len(lines) and not lines[j].startswith('```'):
                j += 1
            out.append('<pre><code>' + esc('\n'.join(lines[i + 1:j])) + '</code></pre>')
            i = j + 1
        elif m := re.match(r'(#{1,4}) (.*)', line):
            level, text = len(m.group(1)), m.group(2)
            sid = slug_of(text)
            if level == 2:
                toc.append((sid, re.sub(r'`', '', text)))
            out.append(f'<h{level} id="{sid}">{inline(text)}</h{level}>')
            i += 1
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                cells = [c.strip() for c in re.split(r'(?<!\\)\|', lines[i].strip())[1:-1]]
                if not all(re.fullmatch(r':?-+:?', c) for c in cells):
                    rows.append(cells)
                i += 1
            head, *body = rows
            out.append('<div class="table-wrap"><table><thead><tr>' + ''.join(f'<th>{inline(c)}</th>' for c in head) +
                       '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{inline(c.replace(chr(92) + "|", "|"))}</td>' for c in r) + '</tr>' for r in body) +
                       '</tbody></table></div>')
        elif re.match(r'(- |\d+\. )', line):
            tag = 'ol' if line[0].isdigit() else 'ul'
            items = []
            while i < len(lines) and (re.match(r'(- |\d+\. )', lines[i]) or (lines[i].startswith('   ') and items)):
                if re.match(r'(- |\d+\. )', lines[i]):
                    items.append(re.sub(r'^(- |\d+\. )', '', lines[i]))
                else:
                    items[-1] += ' ' + lines[i].strip()
                i += 1
            out.append(f'<{tag}>' + ''.join(f'<li>{inline(t)}</li>' for t in items) + f'</{tag}>')
        elif line.strip() == '':
            i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r'(#{1,4} |```|\||- |\d+\. )', lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append('<p>' + inline(' '.join(para)) + '</p>')
    return '\n'.join(out), toc


for revision in ('v1', 'v1.1'):
    spec = (SOURCE.parent.parent / f'docs/extensions/{revision}.md').read_text()
    title = f'Extension protocol, version {revision[1:]}'
    page_spec = spec.replace('](v1.md)', '](/extensions/v1/)')
    spec_html, spec_toc = markdown(re.sub(r'\A# .*\n', '', page_spec))
    toc = '<nav class="page-toc" aria-label="On this page"><p class="toc-title">Sections</p>' + ''.join(
        f'<a href="#{sid}" data-track="{sid}">{esc(heading)}</a>' for sid, heading in spec_toc) + '</nav>'
    body = f'''<main id="main" class="wrap guide-layout">
    <aside class="guide-sidebar">{guide_nav('extensions')}</aside>
    <div class="guide-main">
      <header class="guide-heading"><h1>{esc(title)}</h1><p>How a program becomes a rhun extension. Also as <a href="/extensions/{revision}/{revision}.md">Markdown</a> for agents, with its <a href="https://github.com/rhun-editor/extension-protocol/blob/main/{revision}/{revision}.abnf">grammar</a> and the manifest's <a href="https://github.com/rhun-editor/extension-protocol/blob/main/{revision}/{revision}.json">JSON Schema</a>.</p></header>
      <article class="guide-content spec" aria-label="Extension protocol">{spec_html}</article>
    </div><aside class="guide-toc">{toc}</aside>
    </main>'''
    target = out / 'extensions' / revision
    target.mkdir(parents=True, exist_ok=True)
    (target / 'index.html').write_text(document(title, 'How a program becomes a rhun extension: messages, permissions and negotiated features.', f'/extensions/{revision}/', body, 'docs-guide'))
    (target / f'{revision}.md').write_text(spec.replace('](v1.md)', '](../v1/v1.md)'))
(out / 'extensions' / 'index.html').write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/docs/extensions/"><link rel="canonical" href="https://rhun.app/docs/extensions/"><title>Extensions</title><a href="/docs/extensions/">Extensions</a>\n')

# The extension catalog: the rhun extensions index (rhun-editor/extensions' latest release, fetched by
# site/build.sh into OUT/extension-index.ini) as cards with rhun://extension Install links, which open
# rhun's Add dialog. Without an index the page says how to install from GitHub.
NEEDS_WORDS = [('documents=write', 'read and change the files you have open'),
               ('documents=read', 'read the files you have open'),
               ('project=write', 'read and change the files in your project'),
               ('project=read', 'read the files in your project'),
               ('home=read', 'read the files in your home folder'),
               ('network=yes', 'use the internet'), ('terminal=yes', 'suggest terminal commands for you to run')]


def read_index(path):
    """index.ini as {'format': N, 'entries': [(owner/name, {key: value})]} (whole-line comments)."""
    entries, current, fmt = [], None, 0
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line[0] in '#;':
            continue
        if line[0] == '[' and line[-1] == ']':
            current = {}
            entries.append((line[1:-1], current))
        elif '=' in line:
            key, value = (part.strip() for part in line.split('=', 1))
            if current is None:
                if key == 'format':
                    fmt = int(value) if value.isdigit() else 0
            else:
                current[key] = value
    return fmt, [(n, e) for n, e in entries if e.get('title') and e.get('version') and e.get('tag')]


def can_words(needs):
    words = [w for k, w in NEEDS_WORDS if k in needs.split()]
    for item in needs.split():
        if item.startswith('run='):
            words.append('run ' + ' '.join(item[4:].split(',')))
    return ', '.join(words) or 'only use its own commands and settings'


index_file = out / 'extension-index.ini'
cards = ''
fmt, entries = read_index(index_file) if index_file.exists() else (0, [])
if fmt == 1:
    entries.sort(key=lambda e: (e[1].get('featured') != 'yes', e[1]['title'].lower()))
    for name, e in entries:
        words = ' '.join([e['title'], name, e.get('description', ''), e.get('keywords', '')]).lower()
        cards += f'''<article class="ext-card" data-words="{esc(words)}">
      <h3>{esc(e['title'])} <span class="ext-name">{esc(name)} · {esc(e['version'])}</span></h3>
      <p>{esc(e.get('description', ''))}</p>
      <p class="ext-can">It can {esc(can_words(e.get('needs', '')))}.</p>
      <p><a class="button" href="rhun://extension/{esc(name)}">Install</a> <span class="ext-or">or in rhun: Install from GitHub, <code>{esc(name)}</code></span></p>
    </article>'''
    intro = ('Every version listed here was reviewed before rhun offers it: the release is pinned by its digest, '
             'and rhun installs updates of these by themselves only when they ask for no more access.')
    listing = f'''<input class="ext-search" type="search" placeholder="Search extensions" aria-label="Search extensions">
    <div class="ext-cards">{cards}</div>
    <script>document.querySelector('.ext-search').addEventListener('input', function (e) {{
      var words = e.target.value.toLowerCase().split(/\\s+/).filter(Boolean);
      document.querySelectorAll('.ext-card').forEach(function (card) {{
        var text = ' ' + card.dataset.words.replace(/[^a-z0-9]+/g, ' ');
        card.hidden = !words.every(function (w) {{ return text.indexOf(' ' + w) >= 0; }});
      }});
    }});</script>'''
else:
    intro = 'The catalog of reviewed extensions appears here once rhun-editor/extensions publishes its index.'
    listing = '<p>Meanwhile, install any extension from GitHub: the puzzle piece in the title bar, then <strong>Install from GitHub…</strong>, then its <code>owner/name</code>.</p>'
body = f'''<main id="main" class="wrap guide-layout">
    <aside class="guide-sidebar">{guide_nav('extensions')}</aside>
    <div class="guide-main">
      <header class="guide-heading"><h1>Extensions</h1><p>{esc(intro)}</p></header>
      <article class="guide-content catalog" aria-label="Extensions">{listing}</article>
    </div>
    </main>'''
(out / 'extensions' / 'catalog').mkdir(parents=True, exist_ok=True)
(out / 'extensions' / 'catalog' / 'index.html').write_text(document('Extensions', 'Reviewed extensions for rhun, with Install links that open rhun.', '/extensions/catalog/', body, 'docs-guide'))

# Keep discovery URLs in sync with the actual generated pages.
sitemap = out / 'sitemap.xml'
xml = sitemap.read_text()
urls = ['/docs/'] + [f'/docs/{p["slug"]}/' for p in pages] + ['/extensions/v1/', '/extensions/v1.1/', '/extensions/catalog/']
sitemap.write_text(xml.replace('</urlset>', ''.join(f'  <url><loc>https://rhun.app{url}</loc></url>\n' for url in urls) + '</urlset>'))
