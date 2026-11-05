#!/usr/bin/env python3
"""Check the actual app framework's OCR engine, model and runtime versions."""
from pathlib import Path
import argparse, subprocess, platform
p=argparse.ArgumentParser(description=__doc__);p.add_argument('app',type=Path);p.add_argument('output',type=Path)
p.add_argument('--arch',default=platform.machine(),choices=['arm64','x86_64']);p.add_argument('--allow-old',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];build=a.output.resolve();build.mkdir(parents=True,exist_ok=True)
frameworks=a.app.resolve().parent if a.app.suffix=='.framework' else a.app.resolve()/'Contents/Frameworks';binary=build/'component-ocr'
subprocess.run(['xcrun','clang++','-std=c++17','-arch',a.arch,'-fobjc-arc','-Wl,-headerpad_max_install_names','-F'+str(frameworks),
    '-I'+str(root/'MP42'),'-I'+str(root/'contrib/Tesseract/include'),'-framework','MP42Foundation','-framework','AppKit','-framework','CoreText','-framework','CoreGraphics',
    str(root/'Tests/component-ocr.mm'),'-o',str(binary)],check=True)
deps=subprocess.check_output(['otool','-L',str(binary)],text=True)
old=next(line.strip().split(' (')[0] for line in deps.splitlines()[1:] if 'MP42Foundation.framework/' in line)
subprocess.run(['install_name_tool','-change',old,str(frameworks/'MP42Foundation.framework/Versions/A/MP42Foundation'),str(binary)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True,stderr=subprocess.DEVNULL)
subprocess.run([str(binary)]+(['--allow-old'] if a.allow_old else []),check=True,timeout=60)
