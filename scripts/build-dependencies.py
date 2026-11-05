#!/usr/bin/env python3
"""Build pinned static dependencies for both macOS architectures.
Sources/checksums are in Dependencies/sources.json. No prebuilt archive is committed.
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path)
p.add_argument('--source-cache',type=Path)
p.add_argument('--tools',type=Path)
p.add_argument('--components',choices=['ocr','ffmpeg','mp4v2','all'],default='all')
a=p.parse_args(); out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
sources=(a.source_cache or out/'sources').resolve();sources.mkdir(parents=True,exist_ok=True)
manifest=json.loads((ROOT/'Dependencies/sources.json').read_text())
# NASM/FFmpeg makefiles cannot reliably handle spaces in source/prefix paths.
# Stable temporary aliases keep the checkout/build directories in the user's project.
alias=Path(tempfile.gettempdir())/('subler-build-'+hashlib.sha256(str(out).encode()).hexdigest()[:16])
alias.mkdir(exist_ok=True)
verified_sources=out/'verified-sources';verified_sources.mkdir(exist_ok=True)
for name,target in [('output',out),('verified-sources',verified_sources)]:
    link=alias/name
    if link.is_symlink():
        if link.resolve()!=target: raise SystemExit('Unexpected build alias target')
    elif link.exists(): raise SystemExit('Unexpected build alias path')
    else: link.symlink_to(target,target_is_directory=True)

tools=(a.tools or out/'tools').resolve()
if not (tools/'bin/cmake').exists():
    subprocess.run([sys.executable,'-m','pip','install','--target',str(tools),'cmake==4.4.4','ninja==1.13.2'],check=True)
env=os.environ.copy();env['PYTHONPATH']=str(tools);env['PATH']=str(tools/'bin')+os.pathsep+env['PATH']
env.pop('HOMEBREW_PREFIX',None);env['PKG_CONFIG_PATH']='';env['PKG_CONFIG_LIBDIR']=''
cmake=str(tools/'bin/cmake'); ctest=str(tools/'bin/ctest')
sdk=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
def run(command,log,cwd=None):
    with open(log,'a') as stream:
        subprocess.run([str(x) for x in command],cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,check=True)
prepared={}
def source(name):
    if name in prepared:return prepared[name]
    item=manifest[name];archive=sources/item['archive'];folder=verified_sources/item['directory']
    if not archive.exists():
        subprocess.run(['curl','--fail','--location','--retry','2','--silent','--show-error',item['url'],'-o',str(archive)],check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']:
        raise SystemExit('Source checksum mismatch: '+name)
    # Never compile a possibly modified extracted cache. Re-extract each source
    # once per rebuild from the checked archive, and apply only committed patches.
    if folder.exists():shutil.rmtree(folder)
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            target=verified_sources/member.name
            if not target.resolve().is_relative_to(folder.resolve()):raise SystemExit('Unsafe source archive path')
            if member.issym() or member.islnk():
                link=(target.parent/member.linkname) if member.issym() else verified_sources/member.linkname
                if not link.resolve().is_relative_to(folder.resolve()):raise SystemExit('Unsafe source archive link')
        bundle.extractall(verified_sources)
    for patch in item.get('patches',[]):
        subprocess.run(['/usr/bin/patch','-p1','-F','0','-s','-t','-C','-i',str(ROOT/'Dependencies'/patch)],cwd=folder,check=True)
        subprocess.run(['/usr/bin/patch','-p1','-F','0','-s','-t','-i',str(ROOT/'Dependencies'/patch)],cwd=folder,check=True)
    # Ensure cached object timestamps cannot hide a previous modified extraction.
    for path in folder.rglob('*'):
        if path.is_file() and not path.is_symlink():os.utime(path,None)
    prepared[name]=alias/'verified-sources'/item['directory']
    return prepared[name]
# Include recipe, exact sources and toolchain in the completion fingerprint.
fingerprint=hashlib.sha256((Path(__file__).read_bytes()+(ROOT/'Dependencies/sources.json').read_bytes()+b''.join(p.read_bytes() for p in sorted((ROOT/'Dependencies/patches').glob('*.patch')))+(ROOT/'Tests/image-codecs.c').read_bytes()+subprocess.check_output(['xcodebuild','-version']))).hexdigest()
stamp=out/(a.components+'-complete.json')
if stamp.exists():
    previous=json.loads(stamp.read_text())
    outputs=previous.get('outputs',{})
    intact=bool(outputs) and all((out/name).is_file() and hashlib.sha256((out/name).read_bytes()).hexdigest()==digest for name,digest in outputs.items())
    if previous.get('fingerprint')==fingerprint and intact:
        print('Reusing verified dependency build:',a.components,flush=True);sys.exit(0)
logs=out/'logs';logs.mkdir(exist_ok=True)
def configure_build(name,arch,options,install=True,target=None):
    prefix=out/arch/'ocr';build=out/arch/(name+'-verified-build');log=logs/(name+'-'+arch+'.log')
    common=['-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES='+arch,
            '-DCMAKE_SYSTEM_NAME=Darwin','-DCMAKE_SYSTEM_PROCESSOR='+arch,'-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
            '-DCMAKE_OSX_SYSROOT='+sdk,'-DCMAKE_INSTALL_PREFIX='+str(prefix),'-DBUILD_SHARED_LIBS=OFF',
            '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF',
            '-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF']
    run([cmake,'-S',source(name),'-B',build]+common+options,log)
    command=[cmake,'--build',build,'--parallel','6']
    if target: command+=['--target',target]
    run(command,log)
    if install:run([cmake,'--install',build],log)
    print('Built',name,arch,flush=True)
    return prefix,build,log
if a.components in ['ocr','ffmpeg','all']:
    nasm_source=source('nasm');nasm_build=alias/'output/nasm-verified-build';nasm_prefix=alias/'output/host-tools'
    nasm_build.mkdir(exist_ok=True)
    log=logs/'nasm.log'
    run([nasm_source/'configure','--prefix='+str(nasm_prefix)],log,cwd=nasm_build)
    run(['make','-j6'],log,cwd=nasm_build);run(['make','install'],log,cwd=nasm_build)
    env['PATH']=str(nasm_prefix/'bin')+os.pathsep+env['PATH']

if a.components in ['ocr','all']:
    for arch in ['arm64','x86_64']:
        prefix=out/arch/'ocr';prefix.mkdir(parents=True,exist_ok=True)
        configure_build('png',arch,['-DPNG_FRAMEWORK=OFF','-DPNG_SHARED=ON','-DPNG_STATIC=ON','-DPNG_TESTS=ON','-DPNG_TOOLS=OFF'])
        configure_build('jpeg',arch,['-DENABLE_SHARED=OFF','-DENABLE_STATIC=ON','-DWITH_TURBOJPEG=OFF','-DWITH_TOOLS=ON','-DWITH_TESTS=ON','-DWITH_SIMD=ON','-DCMAKE_ASM_NASM_COMPILER='+str(alias/'output/host-tools/bin/nasm')])
        configure_build('tiff',arch,['-Dtiff-tools=OFF','-Dtiff-tests=ON','-Dtiff-contrib=OFF','-Dtiff-docs=OFF','-Dtiff-cxx=OFF',
            '-DCMAKE_PREFIX_PATH='+str(prefix),'-Djpeg=ON','-Dold-jpeg=ON','-Djbig=OFF','-Dwebp=OFF','-Dzstd=OFF','-Dlzma=OFF','-Dlerc=OFF','-Dlibdeflate=OFF','-Dtiff-opengl=OFF'])
        configure_build('leptonica',arch,['-DCMAKE_PREFIX_PATH='+str(prefix),'-DPNG_LIBRARY='+str(prefix/'lib/libpng16.a'),
            '-DPNG_LIBRARY_RELEASE='+str(prefix/'lib/libpng16.a'),'-DPNG_PNG_INCLUDE_DIR='+str(prefix/'include'),'-DBUILD_PROG=OFF',
            '-DENABLE_PNG=ON','-DENABLE_TIFF=ON','-DENABLE_ZLIB=ON','-DJPEG_LIBRARY='+str(prefix/'lib/libjpeg.a'),
            '-DJPEG_INCLUDE_DIR='+str(prefix/'include'),'-DENABLE_JPEG=ON','-DENABLE_GIF=OFF','-DENABLE_WEBP=OFF','-DENABLE_OPENJPEG=OFF'])
        # A real codec round trip supplies the TIFF result CMake cannot execute
        # automatically in cross-compilation mode. Intel is exercised via Rosetta.
        probe=out/arch/'image-codecs'
        run(['xcrun','clang','-arch',arch,'-mmacosx-version-min=13.0','-I'+str(prefix/'include'),
             str(ROOT/'Tests/image-codecs.c'),prefix/'lib/libleptonica.a',prefix/'lib/libpng16.a',prefix/'lib/libtiff.a',prefix/'lib/libjpeg.a','-lz','-lm','-o',probe],logs/('image-codecs-'+arch+'.log'))
        run([probe],logs/('image-codecs-'+arch+'.log'))
        # Leptonica's generated package omits imported target definitions needed
        # by Tesseract's configuration probes. Resolve only this build artifact.
        package=prefix/'lib/cmake/leptonica/LeptonicaTargets.cmake'
        package.write_text(package.read_text().replace('ZLIB::ZLIB',sdk+'/usr/lib/libz.tbd').replace('JPEG::JPEG',str(prefix/'lib/libjpeg.a')))
        _,build,_=configure_build('tesseract',arch,['-DCMAKE_PREFIX_PATH='+str(prefix),'-DBUILD_TRAINING_TOOLS=OFF',
            '-DBUILD_TESTS=OFF','-DOPENMP_BUILD=OFF','-DGRAPHICS_DISABLED=ON','-DDISABLE_ARCHIVE=ON','-DDISABLE_CURL=ON',
            '-DENABLE_NATIVE=OFF','-DENABLE_CCACHE=OFF','-DLEPT_TIFF_RESULT=0'],install=False,target='libtesseract')
        shutil.copytree(source('tesseract')/'include/tesseract',prefix/'include/tesseract',dirs_exist_ok=True)
        shutil.copy2(build/'include/tesseract/version.h',prefix/'include/tesseract/version.h')
        shutil.copy2(build/'libtesseract.a',prefix/'lib/libtesseract.a')
    universal=out/'ocr';(universal/'lib').mkdir(parents=True,exist_ok=True)
    shutil.copytree(out/'arm64/ocr/include',universal/'include',dirs_exist_ok=True)
    for name in ['libtesseract.a','libleptonica.a','libpng16.a','libtiff.a','libjpeg.a']:
        subprocess.run(['lipo','-create',str(out/'arm64/ocr/lib'/name),str(out/'x86_64/ocr/lib'/name),'-output',str(universal/'lib'/name)],check=True)
    # Keep the historical Leptonica filename while linking JPEG explicitly.
    shutil.copy2(universal/'lib/libleptonica.a',universal/'lib/liblept.a')
    for arch in ['arm64','x86_64']:
        for name in ['png','jpeg','tiff']:
            run([ctest,'--test-dir',out/arch/(name+'-verified-build'),'--output-on-failure','--no-tests=error','--parallel','4'],logs/(name+'-'+arch+'-tests.log'))
    licenses=universal/'licenses';licenses.mkdir(exist_ok=True)
    for name in ['tesseract','leptonica','png','tiff','jpeg']:
        dest=licenses/name;dest.mkdir(exist_ok=True)
        for item in source(name).iterdir():
            if item.is_file() and (('license' in item.name.lower() or item.name.upper().startswith(('COPYING','README.LEGAL','README.IJG'))) ):shutil.copy2(item,dest/item.name)
    print('OCR universal archives and upstream image-library tests complete',flush=True)
if a.components in ['ffmpeg','all']:
    decoders=['dvdsub','pgssub','aac','mp3','mp2','mp1','ac3','eac3','truehd','alac','opus','vorbis','flac','mlp','dca',
              'pcm_f32be','pcm_f32le','pcm_f64be','pcm_f64le','pcm_s16be','pcm_s16le','pcm_s16le_planar',
              'pcm_s24be','pcm_s24le','pcm_s32be','pcm_s32le','pcm_s8','pcm_u8','pcm_u16be','pcm_u16le','pcm_u24be','pcm_u24le']
    for arch in ['arm64','x86_64']:
        build=alias/'output'/arch/'ffmpeg-verified-build';prefix=alias/'output'/arch/'ffmpeg';build.mkdir(parents=True,exist_ok=True)
        log=logs/('ffmpeg-'+arch+'.log')
        options=['--disable-programs','--disable-filters','--disable-everything','--disable-avdevice','--disable-swscale',
                 '--disable-autodetect','--disable-shared','--enable-static','--disable-iconv','--arch='+arch,'--target-os=darwin',
                 '--enable-cross-compile','--cc=clang','--prefix='+str(prefix),
                 '--extra-cflags=-arch '+arch+' -mmacosx-version-min=13.0',
                 '--extra-ldflags=-arch '+arch+' -mmacosx-version-min=13.0',
                 '--enable-encoder=ac3','--enable-filter=aresample','--enable-parser=opus','--enable-parser=h264',
                 '--enable-parser=hevc','--enable-muxer=opus']+['--enable-decoder='+name for name in decoders]
        run([source('ffmpeg')/'configure']+options,log,cwd=build)
        run(['make','-j6'],log,cwd=build);run(['make','install'],log,cwd=build)
        print('Built FFmpeg',arch,flush=True)
    universal=out/'ffmpeg';(universal/'lib').mkdir(parents=True,exist_ok=True)
    shutil.copytree(out/'arm64/ffmpeg/include',universal/'include',dirs_exist_ok=True)
    for name in ['avcodec','avformat','avfilter','avutil','swresample']:
        subprocess.run(['lipo','-create',str(out/'arm64/ffmpeg/lib'/('lib'+name+'.a')),str(out/'x86_64/ffmpeg/lib'/('lib'+name+'.a')),'-output',str(universal/'lib'/('lib'+name+'.a'))],check=True)
    licenses=universal/'licenses';licenses.mkdir(exist_ok=True)
    for path in source('ffmpeg').glob('COPYING*'):shutil.copy2(path,licenses/path.name)
    print('FFmpeg universal archives complete',flush=True)
if a.components in ['mp4v2','all']:
    for arch in ['arm64','x86_64']:
        prefix=out/arch/'mp4v2';source_path=source('mp4v2');build=out/arch/('mp4v2-build-'+hashlib.sha256(str(source_path).encode()).hexdigest()[:12]);log=logs/('mp4v2-'+arch+'.log')
        run([cmake,'-S',source('mp4v2'),'-B',build,'-G','Ninja','-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
            '-DCMAKE_OSX_ARCHITECTURES='+arch,'-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0','-DCMAKE_BUILD_TYPE=Release',
            '-DBUILD_SHARED=OFF','-DBUILD_UTILS=OFF','-DCMAKE_INSTALL_PREFIX='+str(prefix)],log)
        run([cmake,'--build',build,'--parallel','6'],log);run([cmake,'--install',build],log)
    universal=out/'mp4v2';(universal/'lib').mkdir(parents=True,exist_ok=True)
    shutil.copytree(out/'arm64/mp4v2/include',universal/'include',dirs_exist_ok=True)
    (universal/'include/module.modulemap').write_text('module CMP42 [system] [extern_c] { header \"mp4v2/mp4v2.h\" export * }\n')
    subprocess.run(['lipo','-create',str(out/'arm64/mp4v2/lib/libmp4v2.a'),str(out/'x86_64/mp4v2/lib/libmp4v2.a'),'-output',str(universal/'lib/libmp4v2.a')],check=True)
    licenses=universal/'licenses';licenses.mkdir(exist_ok=True)
    for path in source('mp4v2').glob('COPYING*'):shutil.copy2(path,licenses/path.name)
    print('MP4v2 universal archive complete',flush=True)
prefixes=['ocr','ffmpeg','mp4v2'] if a.components=='all' else [a.components]
outputs={}
for prefix in prefixes:
    for path in sorted((out/prefix).rglob('*')):
        if path.is_file():outputs[str(path.relative_to(out))]=hashlib.sha256(path.read_bytes()).hexdigest()
stamp.write_text(json.dumps({'fingerprint':fingerprint,'components':a.components,'outputs':outputs},indent=2)+'\n')
