#!/usr/bin/env python3
"""Regression checks for trusted archive extraction, with no network/build tools."""
import ast, hashlib, io, os, shutil, subprocess, sys, tarfile, tempfile, unittest
from pathlib import Path
BUILDER=Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'scripts/build-dependencies.py'
class SourceVerification(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name).resolve()
        self.cache=self.root/'cache';self.verified=self.root/'verified';self.alias=self.root/'alias'
        for folder in [self.cache,self.verified,self.alias]:folder.mkdir()
        (self.alias/'sources').symlink_to(self.cache,target_is_directory=True)
        (self.alias/'verified-sources').symlink_to(self.verified,target_is_directory=True)
        self.archive=self.cache/'sample.tar.gz'
        with tarfile.open(self.archive,'w:gz') as bundle:
            data=b'trusted\n';item=tarfile.TarInfo('package/payload.c');item.size=len(data);bundle.addfile(item,io.BytesIO(data))
        self.item={'archive':self.archive.name,'directory':'package','sha256':hashlib.sha256(self.archive.read_bytes()).hexdigest(),'url':'https://invalid.example/never-requested'}
        function=next(n for n in ast.parse(BUILDER.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='source')
        module=ast.Module(body=[function],type_ignores=[])
        self.globals={'ROOT':self.root,'manifest':{'sample':self.item},'sources':self.cache,'verified_sources':self.verified,'alias':self.alias,
                      'prepared':{},'hashlib':hashlib,'shutil':shutil,'tarfile':tarfile,'subprocess':subprocess,'os':os}
        exec(compile(module,str(BUILDER),'exec'),self.globals)
    def tearDown(self):self.temporary.cleanup()
    def test_modified_extractions_do_not_replace_checked_archive(self):
        for parent in [self.cache,self.verified]:
            folder=parent/'package';folder.mkdir();(folder/'payload.c').write_text('tampered\n')
        folder=self.globals['source']('sample')
        self.assertEqual((folder/'payload.c').read_bytes(),b'trusted\n')
    def test_modified_patched_cache_does_not_replace_reviewed_patch(self):
        patch=self.root/'Dependencies/patches/fix.patch';patch.parent.mkdir(parents=True)
        patch.write_text('diff --git a/payload.c b/payload.c\n--- a/payload.c\n+++ b/payload.c\n@@ -1 +1 @@\n-trusted\n+patched\n')
        self.item['patches']=['patches/fix.patch']
        cached=self.cache/('package-subler-'+hashlib.sha256(patch.read_bytes()).hexdigest()[:12]);cached.mkdir();(cached/'payload.c').write_text('tampered patch\n')
        folder=self.globals['source']('sample')
        self.assertEqual((folder/'payload.c').read_bytes(),b'patched\n')
    def test_corrupt_archive_is_rejected(self):
        self.archive.write_bytes(b'corrupt')
        with self.assertRaises(SystemExit):self.globals['source']('sample')
if __name__=='__main__':unittest.main()
