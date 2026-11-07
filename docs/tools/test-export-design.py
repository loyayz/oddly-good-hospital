"""Focused export contracts; run with the pinned docs requirements installed."""
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('export_design', TOOLS / 'export-design.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class Book(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids, self.fragments, self.images, self.downloads, self.text, self.local_links = [], [], [], [], [], []
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if attrs.get('href', '').startswith('#'): self.fragments.append(attrs['href'][1:])
        if 'href' in attrs and not attrs['href'].startswith(('#', 'http:', 'https:', 'data:')): self.local_links.append(attrs['href'])
        if tag == 'img': self.images.append(attrs.get('src', ''))
        if 'download' in attrs: self.downloads.append((attrs['download'], attrs['href']))
    def handle_data(self, text): self.text.append(text)


class ExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document, cls.digest, cls.count = exporter.render_book()
        cls.book = Book(cls.document)
    def test_all_chapters_and_links(self):
        self.assertEqual(self.count, 13)
        self.assertEqual(len(self.book.ids), len(set(self.book.ids)))
        self.assertFalse(set(self.book.fragments) - set(self.book.ids))
        from urllib.parse import unquote
        for href in self.book.local_links:
            self.assertTrue((TOOLS.parent / unquote(href.split('#')[0])).exists(), href)
    def test_design_only_chapters(self):
        ids = [c['id'] for c in json.loads((TOOLS / 'design-chapters.json').read_text(encoding='utf-8'))]
        self.assertIn('atlas', ids)
        for process in ['implementation', 'stage01-spec', 'stage01-feasibility', 'stage02-stage03-spec', 'stage02-benchmark', 'stage03-performance', 'stage04-stage24-spec', 'stage25-stage28-spec', 'stage04-stage24-delivery', 'report']:
            self.assertNotIn(process, ids)
            self.assertNotIn(process, self.book.ids)
    def test_chinese_version_and_current_source(self):
        self.assertIn('怪好的医院', self.document)
        self.assertIn('完整产品方案 · 1.97.0', self.document)
        self.assertIn('稳定', ''.join(self.book.text))
        self.assertEqual(len(self.digest), 64)
    def test_literal_braces_preserved(self):
        self.assertIn('cue_{context_id}', ''.join(self.book.text))
        self.assertIn('\"conditions\":{}', ''.join(self.book.text))
        self.assertIn('{disease}', ''.join(self.book.text))
    def test_existing_heading_anchors(self):
        self.assertIn('simulation--section-1', self.book.ids)
        self.assertIn('simulation--section-2', self.book.ids)
    def test_repository_resources(self):
        from urllib.parse import unquote
        self.assertEqual(len(self.book.images), 1)
        image = (TOOLS.parent / unquote(self.book.images[0])).resolve()
        self.assertEqual(image, (TOOLS.parent / 'assets/hospital-concept.png').resolve())
        self.assertTrue(image.is_file())
        self.assertNotIn('base64,', self.document)
        self.assertNotIn('<script', self.document)
        self.assertGreater(len(self.book.downloads), 0)
        downloads = []
        for name, uri in self.book.downloads:
            path = (TOOLS.parent / unquote(uri)).resolve()
            self.assertTrue(path.is_relative_to(TOOLS.parent.parent))
            self.assertEqual(path.name, name)
            self.assertTrue(path.is_file())
            self.assertEqual(path.read_bytes(), next(TOOLS.parent.rglob(name)).read_bytes())
            downloads.append((name, uri))
        self.assertGreater(len(downloads), 0)
    def test_resource_boundaries(self):
        from unittest.mock import patch
        from urllib.parse import unquote
        with tempfile.TemporaryDirectory(prefix='resource boundaries ') as directory:
            root = Path(directory) / 'repo'
            root.mkdir()
            asset = root / '中文 asset.json'
            asset.write_text('{"x":1}', encoding='utf-8')
            outside = Path(directory) / 'outside.json'
            outside.write_text('{}')
            link = root / 'escape.json'
            link.symlink_to(outside)
            with patch.object(exporter, 'REPOSITORY', root):
                output = root / 'docs' / 'book.html'
                uri = exporter.local_reference(asset, output)
                self.assertEqual(uri, exporter.local_reference(asset, output))
                self.assertEqual((output.parent / unquote(uri)).resolve(), asset)
                with self.assertRaises(ValueError): exporter.local_reference(outside, output)
                with self.assertRaises(ValueError): exporter.local_reference(link, output)
                with self.assertRaises(ValueError): exporter.local_reference(root / 'missing.json', output)
    def test_deterministic(self):
        self.assertEqual(exporter.render_book(), (self.document, self.digest, self.count))
    def test_bash_custom_path_spaces_and_check(self):
        import os
        with tempfile.TemporaryDirectory(prefix='book test ') as directory:
            target = Path(directory) / 'output book.html'
            env = dict(os.environ, PYTHON=sys.executable)
            cmd = ['bash', str(TOOLS / 'export-design.sh'), str(target)]
            subprocess.run(cmd, cwd=directory, env=env, check=True, capture_output=True)
            self.assertEqual(target.read_bytes(), exporter.render_book(target)[0].encode())
            subprocess.run(cmd + ['--check'], cwd=directory, env=env, check=True, capture_output=True)
            target.write_text('stale')
            result = subprocess.run(cmd + ['--check'], cwd=directory, env=env, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(target.read_text(), 'stale')
    def test_failed_render_preserves_target(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'book.html'
            target.write_text('original')
            with patch.object(sys, 'argv', ['export-design.py', str(target)]), patch.object(exporter, 'render_book', side_effect=ValueError('test malformed source')):
                self.assertEqual(exporter.main(), 1)
            self.assertEqual(target.read_text(), 'original')
            self.assertEqual(list(Path(directory).iterdir()), [target])


if __name__ == '__main__': unittest.main()
