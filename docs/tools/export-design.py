#!/usr/bin/env python3
"""Build the offline design book; shared by the Bash and PowerShell launchers."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote, unquote

TOOLS = Path(__file__).resolve().parent
DOCS = TOOLS.parent
REPOSITORY = DOCS.parent


def local_reference(path, output, fragment=''):
    path = path.resolve()
    if not path.is_relative_to(REPOSITORY.resolve()):
        raise ValueError(f'Local resource escapes the repository: {path}')
    if not path.is_file():
        raise ValueError(f'Missing local resource: {path}')
    relative = quote(os.path.relpath(path, output.parent).replace(os.sep, '/'), safe='/')
    return html.escape(relative + fragment, quote=True)


def render_book(output=None):
    output = (output or DOCS / 'product-design.html').resolve()
    from markdown_it import MarkdownIt
    from mdit_py_plugins.tasklists import tasklists_plugin
    parser = MarkdownIt('commonmark', {'html': True}).enable(['table', 'strikethrough']).use(tasklists_plugin)
    chapters = json.loads((TOOLS / 'design-chapters.json').read_text(encoding='utf-8'))
    generated = json.loads(subprocess.check_output([sys.executable, '-B', '-X', 'utf8', str(TOOLS / 'content-atlas.py')], text=True, encoding='utf-8'))
    catalog = json.loads((DOCS / 'data/content-catalog.json').read_text(encoding='utf-8'))
    by_path = {(DOCS / c['source']).resolve(): c['id'] for c in chapters if c['kind'] == 'File'}
    digest_source, sections = [], []
    for chapter in chapters:
        if chapter['kind'] == 'Generated':
            markdown, source_dir = generated[chapter['source']], DOCS
        else:
            path = DOCS / chapter['source']
            # Preserve source newlines in the digest, matching ReadAllText.
            with path.open(encoding='utf-8', newline='') as stream:
                markdown = stream.read()
            source_dir = path.parent
        digest_source.append(markdown)
        tokens = parser.parse(markdown)
        seen = set()
        for index, token in enumerate(tokens):
            if token.type == 'heading_open':
                text = tokens[index + 1].content
                slug = re.sub(r'[^a-z0-9_ -]', '', text.lower())
                slug = re.sub(r'^[^a-z]+', '', slug).strip().replace(' ', '-') or 'section'
                identity, count = slug, 0
                while identity in seen:
                    count += 1
                    identity = f'{slug}-{count}'
                seen.add(identity)
                token.attrSet('id', identity)
        body = parser.renderer.render(tokens, parser.options, {})
        body = re.sub(r'\bid="([^"]+)"', lambda m: f'id="{chapter["id"]}--{m[1]}"', body)
        def href(match):
            value = html.unescape(match[1])
            if re.match(r'^[a-zA-Z]+:', value):
                return match[0]
            if value.startswith('#'):
                return f'href="#{chapter["id"]}--{value[1:]}"'
            path = (source_dir / unquote(value.split('#')[0])).resolve()
            if path == (DOCS / 'product-design.html').resolve():
                return 'href="#' + (value.split('#', 1)[1] if '#' in value else 'simulation') + '"'
            if path in by_path:
                return f'href="#{by_path[path]}"'
            if path == (DOCS / 'assets/hospital-concept.png').resolve():
                return 'href="#scene-concept-image"'
            if path.suffix == '.json' and path.is_file():
                return f'href="{local_reference(path, output)}" download="{html.escape(path.name, quote=True)}"' 
            fragment = '#' + value.split('#', 1)[1] if '#' in value else ''
            return f'href="{local_reference(path, output, fragment)}"' 
        body = re.sub(r'href="([^"]+)"', href, body)
        def image(match):
            value = html.unescape(match[1])
            if re.match(r'^[a-zA-Z]+:', value):
                return match[0]
            path = (source_dir / unquote(value)).resolve()
            return f'id="scene-concept-image" src="{local_reference(path, output)}"' 
        body = re.sub(r'src="([^"]+)"', image, body)
        body = body.replace('<table>', '<div class="table-wrap"><table>').replace('</table>', '</table></div>')
        sections.append(f'<section class="chapter" id="{chapter["id"]}">{body}</section>')
    digest = hashlib.sha256(''.join(digest_source).encode('utf-8')).hexdigest()
    values = {'digest': digest, 'designVersion': html.escape(catalog['content_version']),
              'toc': '\n'.join(f'<li><a href="#{c["id"]}">{html.escape(c["title"])}</a></li>' for c in chapters),
              'sectionHtml': '\n'.join(sections)}
    document = (TOOLS / 'design-book.html').read_text(encoding='utf-8')
    for key, value in values.items():
        document = document.replace('{{' + key + '}}', value)
    return document, digest, len(chapters)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', nargs='?', help='Output HTML path; empty uses the default.')
    ap.add_argument('--check', action='store_true', help='Fail if the target differs; never write it.')
    args = ap.parse_args()
    args.output = Path(args.output) if args.output else DOCS / 'product-design.html'
    try:
        document, digest, count = render_book(args.output)
        data = document.encode('utf-8')
        if args.check:
            if not args.output.is_file() or args.output.read_bytes() != data:
                print(f'Design book is stale: {args.output}', file=sys.stderr)
                return 1
        else:
            # All reads/rendering finish before replacing the existing book.
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=args.output.resolve().parent, delete=False) as stream:
                    temporary = Path(stream.name)
                    stream.write(data)
                os.replace(temporary, args.output)
            finally:
                if temporary is not None and temporary.exists():
                    temporary.unlink()
        print(f'BOOK_CHAPTERS={count}\nBOOK_BYTES={len(data)}\nSOURCE_SHA256={digest}')
        return 0
    except (OSError, ValueError, ImportError, subprocess.CalledProcessError) as error:
        print(f'Design book export failed; existing book was not changed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
