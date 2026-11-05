#!/usr/bin/env python3
"""Exercise publication and stamp reuse without downloading or compiling sources."""
import ast, hashlib, shutil, subprocess, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
BUILDER=Path(__file__).resolve().parents[1]/'scripts/build-dependencies.py'
class Arm64Recipe(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        tree=ast.parse(BUILDER.read_text())
        functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['reusable_stamp','publish_archive']]
        self.scope={'hashlib':hashlib,'shutil':shutil,'subprocess':subprocess}
        exec(compile(ast.Module(body=functions,type_ignores=[]),str(BUILDER),'exec'),self.scope)
    def tearDown(self):self.temp.cleanup()
    def test_publication_copies_arm64_bytes_and_rejects_other_slices(self):
        source=self.root/'source.a';source.write_bytes(b'archive');dest=self.root/'published.a'
        with patch.object(subprocess,'check_output',return_value='arm64\n'):
            self.scope['publish_archive'](source,dest)
        self.assertEqual(dest.read_bytes(),source.read_bytes())
        for slices in ['x86_64\n','arm64 x86_64\n','']:
            with patch.object(subprocess,'check_output',return_value=slices),self.assertRaises(SystemExit):
                self.scope['publish_archive'](source,dest)
    def test_cache_requires_architecture_fingerprint_and_intact_outputs(self):
        output=self.root/'archive.a';output.write_bytes(b'arm64')
        stamp={'architecture':'arm64','fingerprint':'recipe','outputs':{'archive.a':hashlib.sha256(output.read_bytes()).hexdigest()}}
        reuse=self.scope['reusable_stamp']
        self.assertTrue(reuse(stamp,'recipe',self.root))
        for field,value in [('architecture','universal'),('architecture',None),('fingerprint','old'),('outputs',{})]:
            self.assertFalse(reuse(dict(stamp,**{field:value}),'recipe',self.root))
        output.write_bytes(b'modified');self.assertFalse(reuse(stamp,'recipe',self.root))
        output.unlink();self.assertFalse(reuse(stamp,'recipe',self.root))
    def test_recipe_architecture_loops_and_publication(self):
        tree=ast.parse(BUILDER.read_text())
        loops=[n for n in ast.walk(tree) if isinstance(n,ast.For) and isinstance(n.target,ast.Name) and n.target.id=='arch']
        self.assertEqual(len(loops),4)
        for loop in loops:self.assertEqual(ast.literal_eval(loop.iter),['arm64'])
        self.assertNotIn("'-create'",BUILDER.read_text())
if __name__=='__main__':unittest.main()
