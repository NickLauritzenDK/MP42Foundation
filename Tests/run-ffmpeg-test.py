#!/usr/bin/env python3
"""Separate actual-framework FFmpeg checks from standalone dependency capability checks."""
from pathlib import Path
import argparse, subprocess, platform
p=argparse.ArgumentParser(description=__doc__);p.add_argument('app',type=Path);p.add_argument('output',type=Path)
p.add_argument('--include',type=Path,required=True);p.add_argument('--arch',default=platform.machine(),choices=['arm64','x86_64']);p.add_argument('--allow-old',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];build=a.output.resolve();build.mkdir(parents=True,exist_ok=True)
frameworks=a.app.resolve().parent if a.app.suffix=='.framework' else a.app.resolve()/'Contents/Frameworks'
common=['xcrun','clang','-arch',a.arch,'-I'+str(a.include.resolve()),str(root/'Tests/component-ffmpeg.c')]
binary=build/'framework-ffmpeg'
# No external FFmpeg archives may satisfy a missing framework symbol in this test.
subprocess.run(common+['-DMP42_FRAMEWORK_ONLY','-Wl,-headerpad_max_install_names','-F'+str(frameworks),'-framework','MP42Foundation','-o',str(binary)],check=True)
deps=subprocess.check_output(['otool','-L',str(binary)],text=True)
old=next(line.strip().split(' (')[0] for line in deps.splitlines()[1:] if 'MP42Foundation.framework/' in line)
subprocess.run(['install_name_tool','-change',old,str(frameworks/'MP42Foundation.framework/Versions/A/MP42Foundation'),str(binary)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True,stderr=subprocess.DEVNULL)
subprocess.run([str(binary)]+(['--allow-old'] if a.allow_old else []),check=True,timeout=60)
# The app does not call avfilter/avformat. Check the full configured dependency
# matrix separately, without claiming those unused APIs are in the app binary.
binary=build/'dependency-ffmpeg'
subprocess.run(common+['-L'+str(a.include.resolve().parent/'lib'),'-lavformat','-lavfilter','-lswresample','-lavcodec','-lavutil',
    '-lz','-lbz2','-liconv','-framework','CoreFoundation','-framework','CoreVideo','-framework','VideoToolbox','-framework','AudioToolbox','-o',str(binary)],check=True)
subprocess.run([str(binary)]+(['--allow-old'] if a.allow_old else []),check=True,timeout=60)
