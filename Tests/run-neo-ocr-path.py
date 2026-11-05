#!/usr/bin/env python3
"""Run the production OCR support-path method in controlled host bundles."""
from pathlib import Path
import argparse,plistlib,subprocess
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
source=(root/'MP42/MP42TesseractOCR.mm').read_text();method=source[source.index('- (NSURL *)appSupporTessdatatUrl'):source.index('- (BOOL)tessdataAvailableForLanguage:')]
code='#import <Foundation/Foundation.h>\n@interface OCRPathProbe:NSObject\n- (NSURL *)appSupporTessdatatUrl;\n@end\n@implementation OCRPathProbe\n'+method+'\n@end\nint main(int argc,const char **argv){@autoreleasepool{NSString *path=[[[OCRPathProbe alloc]init]appSupporTessdatatUrl].path;NSString *suffix=[@(argv[1]) stringByAppendingPathComponent:@"tessdata/v4"];printf("%s\\n",path.UTF8String);return ![path hasSuffix:suffix];}}\n'
file=out/'probe.m';file.write_text(code)
for host,folder in [('neo','Subler Neo'),('legacy','Subler')]:
 bundle=out/(host+'.app');mac=bundle/'Contents/MacOS';mac.mkdir(parents=True,exist_ok=True);info={'CFBundleIdentifier':'test.'+host,'CFBundleExecutable':'PathProbe'}
 if host=='neo':info['MP42ApplicationSupportDirectoryName']='Subler Neo'
 (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['xcrun','clang','-arch','arm64','-fobjc-arc','-framework','Foundation',str(file),'-o',str(mac/'PathProbe')],check=True)
 subprocess.run([str(mac/'PathProbe'),folder],check=True,timeout=10)
 print('PASS:',host,'OCR path is isolated')
