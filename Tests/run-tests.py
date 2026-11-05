#!/usr/bin/env python3
"""Compile real-framework regression tests; compare editing traces with official 1.9.5.
Usage: run-tests.py APP_OR_FRAMEWORK BUILD_DIR [--record-reference]
Only use --record-reference with the verified official release, never a candidate.
"""
from pathlib import Path
import json, subprocess, sys, gzip, hashlib, platform
import argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("framework"); parser.add_argument("build")
parser.add_argument("--record-reference",action="store_true")
parser.add_argument("--media-fixture",type=Path, default=Path(__file__).resolve().parent/"fixtures/tone.m4a")
parser.add_argument("--arch", choices=["arm64","x86_64"], default=platform.machine())
args=parser.parse_args()
framework, build = (Path(p).resolve() for p in [args.framework,args.build])
if framework.suffix == '.app':
    framework = framework / 'Contents/Frameworks/MP42Foundation.framework'
frameworks = framework.parent
build.mkdir(parents=True, exist_ok=True)
tests = Path(__file__).resolve().parent
if args.record_reference:
    provenance=json.loads((tests/'reference-provenance.json').read_text())
    digest=hashlib.sha256((framework/'Versions/A/MP42Foundation').read_bytes()).hexdigest()
    if digest != provenance['framework_sha256']:
        raise SystemExit('Reference recording requires the checksum-verified official 1.9.5 framework')
programs=['track-editing', 'track-state', 'baseline-tests']
if args.media_fixture: programs.append('media-roundtrip')
for program in programs:
    exe = build / program
    subprocess.run(['xcrun','clang','-arch',args.arch,'-fobjc-arc','-Wl,-headerpad_max_install_names',
        '-fmodules-cache-path='+str(build/'module-cache'),'-I'+str(tests.parent/'contrib/mp4v2'),'-F'+str(frameworks),
        '-framework','Foundation','-framework','MP42Foundation',
        '-Wl,-rpath,'+str(frameworks), str(tests/(program+'.m')),'-o',str(exe)],check=True)
    deps = subprocess.check_output(['otool','-L',str(exe)],text=True)
    dependency = next(line.strip().split(' (')[0] for line in deps.splitlines()[1:] if 'MP42Foundation.framework/' in line)
    subprocess.run(['install_name_tool','-change',dependency,str(framework/'Versions/A/MP42Foundation'),str(exe)],check=True)
    subprocess.run(['codesign','--force','--sign','-',str(exe)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    command=[str(exe)]
    if program=='media-roundtrip': command += [str(args.media_fixture.resolve()),str(build/'media-output')]
    result = subprocess.run(command,capture_output=True,text=True,timeout=60)
    if result.returncode:
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit(result.returncode)
    if program == 'baseline-tests':
        print(result.stdout.strip())
    else:
        actual = json.loads(result.stdout)
        (build/(program+'-results.json')).write_text(json.dumps(actual,sort_keys=True,separators=(',',':'))+'\n')
        reference = tests/('official-1.9.5-'+program+'.json.gz')
        if args.record_reference:
            if reference.exists():
                if json.loads(gzip.decompress(reference.read_bytes())) != actual: raise SystemExit('Existing reference differs; refusing to overwrite')
                continue
            reference.write_bytes(gzip.compress((json.dumps(actual,sort_keys=True,separators=(',',':'))+'\n').encode(),mtime=0))
            print(f'Recorded {len(actual)} official characterization scenarios')
        else:
            expected = json.loads(gzip.decompress(reference.read_bytes()))
            differences = [key for key in sorted(set(actual)|set(expected)) if actual.get(key)!=expected.get(key)]
            if differences:
                for key in differences[:5]: print('FAIL:',key,'(full results in',build/(program+'-results.json'),')')
                raise SystemExit(f'{len(differences)}/{len(expected)} track editing scenarios differ')
            print(f'PASS ({args.arch}): {len(actual)} {program} scenarios match official 1.9.5')
