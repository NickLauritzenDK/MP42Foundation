#!/usr/bin/env python3
"""Behavioral duration/pitch/EOF tests with generated non-copyrighted PCM."""
import argparse, pathlib, subprocess, wave, math, struct, json, platform
p=argparse.ArgumentParser();p.add_argument('framework',type=pathlib.Path);p.add_argument('output',type=pathlib.Path);p.add_argument('--arch',default=platform.machine(),choices=['arm64','x86_64']);p.add_argument('--dependencies',type=pathlib.Path);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];o=a.output.resolve();o.mkdir(parents=True,exist_ok=True);fw=a.framework.resolve();fw=fw/'Contents/Frameworks/MP42Foundation.framework' if fw.suffix=='.app' else fw;exe=o/'probe'
subprocess.run(['xcrun','clang','-arch',a.arch,'-Wl,-headerpad_max_install_names','-fobjc-arc','-F'+str(fw.parent),'-framework','MP42Foundation','-framework','AppKit',str(r/'Tests/audio-conversion.m'),'-o',str(exe)],check=True)
deps=subprocess.check_output(['otool','-L',str(exe)],text=True);old=next(x.strip().split(' (')[0] for x in deps.splitlines() if 'MP42Foundation.framework/' in x)
subprocess.run(['install_name_tool','-change',old,str(fw/'Versions/A/MP42Foundation'),str(exe)],check=True);subprocess.run(['codesign','-f','-s','-',str(exe)],check=True)
dep=(a.dependencies or r/'build/dependencies').resolve()/'ffmpeg'
resample=o/'resample-probe'
subprocess.run(['xcrun','clang','-arch',a.arch,'-I'+str(dep/'include'),'-I'+str(r/'MP42/muxer'),str(r/'Tests/audio-resample.c'),str(r/'MP42/muxer/audio_resample.c'),'-L'+str(dep/'lib'),'-lswresample','-lavutil','-o',str(resample)],check=True)
subprocess.run([str(resample)],check=True,timeout=15)
failures=[]
def wav_samples(path):
 raw=path.read_bytes();chunks={};pos=12
 while pos+8<=len(raw):
  kind=raw[pos:pos+4];size=struct.unpack_from('<I',raw,pos+4)[0];chunks[kind]=raw[pos+8:pos+8+size];pos+=8+size+(size%2)
 _,channels,rate,_,_,bits=struct.unpack_from('<HHIIHH',chunks[b'fmt ']);assert bits==16
 data=chunks[b'data'];return rate, channels,struct.unpack('<'+'h'*(len(data)//2),data)[::channels]
encoder=o/'encoder-probe'
subprocess.run(['xcrun','clang','-arch',a.arch,'-Wl,-headerpad_max_install_names','-fobjc-arc','-I'+str(r/'MP42'),'-F'+str(fw.parent),'-framework','MP42Foundation','-framework','AppKit',str(r/'Tests/audio-encoder.m'),'-o',str(encoder)],check=True)
subprocess.run(['install_name_tool','-change',old,str(fw/'Versions/A/MP42Foundation'),str(encoder)],check=True)
subprocess.run(['codesign','-f','-s','-',str(encoder)],check=True)
subprocess.run([str(encoder),'unused','decode-rate'],check=True,timeout=10)
subprocess.run([str(encoder),'unused','cancel'],check=True,timeout=5)
raw_ac3=o/'partial.ac3';raw_wav=o/'partial.wav';raw_wav.unlink(missing_ok=True)
subprocess.run([str(encoder),str(raw_ac3)],check=True,timeout=15)
subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(raw_ac3),str(raw_wav)],check=True)
_,_,partial=wav_samples(raw_wav)
peak=max(map(abs,partial[-300:]));print('partial EOF padding peak:',peak,flush=True)
if peak>20:failures.append('partial EOF contains stale PCM')
for rate in (22050,24000,32000,44100,48000,96000):
 # End with silence longer than codec delay: stale final-buffer data must not reappear.
 n=rate*2+137;source=o/f'{rate}.wav';target=o/f'{rate}.mp4';decoded=o/f'{rate}-out.wav'
 with wave.open(str(source),'wb') as w:
  w.setparams((2,2,rate,0,'NONE',''));w.writeframes(b''.join(struct.pack('<hh',*( [int(7000*math.sin(2*math.pi*440*i/rate)) if i<rate*2-rate//5 else 0]*2)) for i in range(n)))
 target.unlink(missing_ok=True);decoded.unlink(missing_ok=True)
 subprocess.run([str(exe),'ac3',str(source),str(target)],check=True,timeout=40)
 result=subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(target),str(decoded)])
 if result.returncode:
  failures.append(f'{rate}: output cannot be decoded');print(rate,'FAIL output cannot be decoded',flush=True);continue
 raw=decoded.read_bytes();chunks={};pos=12
 while pos+8<=len(raw):
  kind=raw[pos:pos+4];size=struct.unpack_from('<I',raw,pos+4)[0];chunks[kind]=raw[pos+8:pos+8+size];pos+=8+size+(size%2)
 _,channels,out_rate,_,_,bits=struct.unpack_from('<HHIIHH',chunks[b'fmt ']);assert bits==16
 data=chunks[b'data'];frames=len(data)//(2*channels)
 samples=struct.unpack('<'+'h'*(len(data)//2),data)[::channels];duration=frames/out_rate;expected=n/rate
 crossings=sum(x<=0<y for x,y in zip(samples[out_rate//2:out_rate],samples[out_rate//2+1:out_rate+1]));pitch=crossings*2
 tail=max(map(abs,samples[-300:]));meta=json.loads(pathlib.Path(str(target)+'.json').read_text());track=next(t for t in meta['tracks'] if 'channels' in t)
 errors=[]
 if abs(duration-expected)>0.07:errors.append(f'duration {duration:.6f} expected {expected:.6f}')
 if abs(pitch-440)>4:errors.append(f'pitch {pitch}')
 if tail>20:errors.append(f'non-silent EOF padding {tail}')
 if out_rate!=48000 or track['timescale']!=48000:errors.append(f'rate/timebase {out_rate}/{track["timescale"]}')
 print(rate, 'FAIL '+', '.join(errors) if errors else f'PASS duration={duration:.6f} pitch={pitch} tail={tail}',flush=True)
 failures.extend(errors)
if failures:raise SystemExit('FAIL: '+str(len(failures))+' audio correctness assertions')
