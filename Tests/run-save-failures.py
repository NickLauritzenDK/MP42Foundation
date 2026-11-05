#!/usr/bin/env python3
"""Exercise missing-source, retry and track-write failure behavior in the actual framework."""
from pathlib import Path
import argparse,subprocess,platform
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('output',type=Path);p.add_argument('--arch',default=platform.machine());a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
fw=a.app.resolve()/'Contents/Frameworks' if a.app.suffix=='.app' else a.app.resolve().parent
exe=out/'save-failures'
subprocess.run(['xcrun','clang','-arch',a.arch,'-fobjc-arc','-Wl,-headerpad_max_install_names','-F'+str(fw),'-framework','MP42Foundation','-framework','AppKit',str(root/'Tests/save-failures.m'),'-o',str(exe)],check=True)
linked=subprocess.check_output(['otool','-L',str(exe)],text=True);old=next(l.strip().split(' (')[0] for l in linked.splitlines()[1:] if 'MP42Foundation.framework/' in l)
subprocess.run(['install_name_tool','-change',old,str(fw/'MP42Foundation.framework/Versions/A/MP42Foundation'),str(exe)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(exe)],check=True)
subprocess.run([str(exe),str(root/'Tests/fixtures/tone.m4a'),str(out/'files')],check=True,timeout=60)
