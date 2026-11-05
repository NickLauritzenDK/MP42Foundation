#!/usr/bin/env python3
"""Compile the production FIFO under its non-ARC ownership mode and exercise cancellation/concurrency."""
from pathlib import Path
import argparse,subprocess,platform
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('output',type=Path);p.add_argument('--arch',default=platform.machine());a=p.parse_args()
r=Path(__file__).resolve().parents[1];o=a.output.resolve();o.mkdir(parents=True,exist_ok=True)
fw=a.app.resolve()/'Contents/Frameworks' if a.app.suffix=='.app' else a.app.resolve().parent
exe=o/'fifo-cancellation'
subprocess.run(['xcrun','clang','-arch',a.arch,'-fno-objc-arc','-I'+str(r/'MP42'),'-F'+str(fw),'-framework','Foundation',str(r/'Tests/fifo-cancellation.m'),str(r/'MP42/MP42Fifo.m'),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True,timeout=15)
