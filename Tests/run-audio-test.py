#!/usr/bin/env python3
"""Compare actual app AAC/AC3 conversion and decoded audio with the release baseline.
Recording is permitted only with the checksum-verified official framework.
Requires access to macOS AudioToolbox (normal unsandboxed developer environment).
"""
from pathlib import Path
import argparse,subprocess,platform,json,gzip,hashlib,base64,struct,array,math
p=argparse.ArgumentParser(description=__doc__);p.add_argument('app',type=Path);p.add_argument('output',type=Path)
p.add_argument('--arch',default=platform.machine(),choices=['arm64','x86_64']);p.add_argument('--record-reference',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];tests=root/'Tests';out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
frameworks=a.app.resolve().parent if a.app.suffix=='.framework' else a.app.resolve()/'Contents/Frameworks'
if a.record_reference:
 expected=json.loads((tests/'reference-provenance.json').read_text())['framework_sha256']
 if hashlib.sha256((frameworks/'MP42Foundation.framework/Versions/A/MP42Foundation').read_bytes()).hexdigest()!=expected:raise SystemExit('Recording requires verified official framework')
exe=out/'audio-conversion'
subprocess.run(['xcrun','clang','-arch',a.arch,'-fobjc-arc','-Wl,-headerpad_max_install_names','-F'+str(frameworks),'-framework','MP42Foundation','-framework','AppKit',str(tests/'audio-conversion.m'),'-o',str(exe)],check=True)
deps=subprocess.check_output(['otool','-L',str(exe)],text=True);old=next(l.strip().split(' (')[0] for l in deps.splitlines()[1:] if 'MP42Foundation.framework/' in l)
subprocess.run(['install_name_tool','-change',old,str(frameworks/'MP42Foundation.framework/Versions/A/MP42Foundation'),str(exe)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(exe)],check=True,stderr=subprocess.DEVNULL)
actual={}
for mode in ['convert','ac3']:
 target=out/(mode+'.mp4');target.unlink(missing_ok=True)
 subprocess.run([str(exe),mode,str(tests/'fixtures/tone.m4a'),str(target)],check=True,timeout=60)
 pcm=out/(mode+'.wav');pcm.unlink(missing_ok=True)
 subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(target),str(pcm)],check=True,timeout=60)
 raw=pcm.read_bytes()
 if raw[:4]!=b'RIFF' or raw[8:12]!=b'WAVE':raise SystemExit('Invalid decoded WAV')
 chunks={};position=12
 while position+8<=len(raw):
  kind=raw[position:position+4];size=struct.unpack_from('<I',raw,position+4)[0]
  chunks[kind]=raw[position+8:position+8+size];position+=8+size+(size%2)
 fmt=chunks[b'fmt '];tag,channels,rate,_,_,bits=struct.unpack_from('<HHIIHH',fmt)
 if bits!=16 or not(tag==1 or tag==65534 and struct.unpack_from('<I',fmt,24)[0]==1):raise SystemExit('Expected decoded 16-bit PCM')
 data=chunks[b'data']
 actual[mode]={'metadata':json.loads(Path(str(target)+'.json').read_text()),'channels':channels,'rate':rate,'frames':len(data)//(channels*2),'pcm':base64.b64encode(data).decode()}

reference=tests/'official-1.9.5-audio-conversion.json.gz'
if a.record_reference:
 if reference.exists():raise SystemExit('Refusing to overwrite reference')
 reference.write_bytes(gzip.compress(json.dumps(actual,sort_keys=True).encode(),mtime=0));print('Recorded official AAC and AC3 conversion reference')
else:
 expected=json.loads(gzip.decompress(reference.read_bytes()))
 for mode,row in actual.items():
  before=expected[mode]
  for key in ['metadata','channels','rate','frames']:
   if row[key]!=before[key]:raise SystemExit('FAIL '+mode+' '+key+' changed: '+str(row[key])+' versus '+str(before[key]))
  samples=array.array('h',base64.b64decode(row['pcm']));old=array.array('h',base64.b64decode(before['pcm']))
  error=math.sqrt(sum((x-y)**2 for x,y in zip(samples,old))/max(1,len(samples)))
  signal=math.sqrt(sum(x*x for x in old)/max(1,len(old)))
  relative=error/max(1,signal)
  print(mode,'relative decoded RMS difference:',relative,'maximum sample delta:',max(abs(x-y) for x,y in zip(samples,old)))
  if relative>0.001:raise SystemExit('FAIL decoded conversion differs by more than 0.1% RMS from baseline')
 print('PASS ('+a.arch+'): actual AAC/AC3 conversion timing, metadata and decoded audio match baseline tolerance')
