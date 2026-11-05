# Pinned dependency builds

The modernization branch builds dependency archives from official source tarballs, not from a third binary repository. `sources.json` records exact versions, URLs and SHA-256 hashes. Local compatibility patches are committed under `patches/`.

## Selected components

| Component | Release baseline | Modernized selection |
| --- | --- | --- |
| Tesseract | 5.0.0 | 5.5.4 |
| Leptonica | 1.82.0 (runtime verified) | 1.87.0 |
| libpng | 1.6.37 (baseline header) | 1.6.59 |
| libtiff | 4.2.0 (baseline source inventory) | 4.7.2 |
| JPEG | Previously bundled/transitive; exact old version not established | libjpeg-turbo 3.2.1 |
| FFmpeg | 4.4 | 9.0.2 |
| MP4v2 | 2.1.3 with Subler-specific APIs | Current Subler source 76799d1d227c1e63204a36ae0949b5e8e9792122 + required Director API |

Sparkle is owned by the application project and pinned there to 2.10.1. System frameworks and zlib/bz2/lzma/iconv continue to come from macOS/SDK; they are not substituted with bundled libraries.

## Rebuild

```sh
python3 scripts/build-dependencies.py build/dependencies --components all
```

Validated on an Apple Silicon Mac with Rosetta, Xcode 27.2/SDK 27.2, macOS 13 deployment target. CMake 4.4.4 and Ninja 1.13.2 are installed only into the chosen build directory from pinned PyPI packages; NASM 3.02 is built from its pinned official archive. No system package manager or global installation is changed. These are tested tool versions, not a claim that every upstream build-tool patch is the newest available.

Separate arm64/x86_64 builds are combined with `lipo`. Tesseract's legacy and LSTM engines remain enabled; host-specific tuning is disabled, and upstream portable ISA dispatch is retained. JPEG's normal SIMD support is built with NASM. Native Intel hardware was not used; x86_64 tests run through Rosetta. The current recipe requires Rosetta to execute its Intel test programs on Apple Silicon.

Archives are checksum-verified before extraction. On a rebuild, sources are re-extracted into a private generated directory and only committed patches are applied, so edited extracted caches cannot replace the official source. A completion stamp covers recipe/manifest/patches/toolchain and the image-codec probe, plus hashes of generated archives, headers and notices. Missing or changed outputs invalidate reuse. A fast cache hit does not rerun tests; use a new output directory for a complete clean build/test.

CMake runs the upstream PNG, JPEG and TIFF tests with `--no-tests=error`. Shared PNG is built solely because upstream's tests require it; the app links the explicit static archive. A separate static-archive probe tests lossless PNG/TIFF and JPEG encoding/decoding before Tesseract's cross-compile TIFF result is supplied.

## FFmpeg configuration and compatibility

The recipe retains the release's 32 decoder choices, AC3 encoder, H.264/HEVC/Opus parsers, resampling and Opus muxer configuration. Programs, unrelated filters/devices, shared builds and external autodetection are disabled. Both CPU architectures retain the configured feature matrix. The app does not use every compiled FFmpeg subsystem: standalone matrix tests and actual-framework checks are reported separately.

Required source changes use const codecs, AVChannelLayout, current supported-layout queries and avcodec_free_context. Track import, mixdown selections and OCR engine policy remain unchanged. The existing `normalize_mix_level` call was already a no-op in libswresample; it is deliberately not translated to `rematrix_maxval`, which would introduce a normalization-policy change.

## MP4v2 compatibility patch

The current official Subler MP4v2 source omits `MP4TagsSetDirector`, although the original shipped header/binary and Subler's unchanged metadata writer require it. The small patch restores that accessor with the same setter pattern as adjacent APIs. A real create/store/reopen test verifies Unicode Director metadata; app audio roundtrips also exercise this field. No unrelated cache, chapter or parser fixes from earlier customized work are carried over.

## Notices and retained source

The builder copies the dependency licenses into each generated prefix; the app build script includes them with its local test bundle. Tesseract: Apache 2.0; Leptonica: BSD-style; PNG/TIFF: their project licenses; JPEG: IJG/BSD-style notices; configured FFmpeg: LGPL 2.1+; MP4v2: MPL 1.1. The combined application remains governed by the upstream project's licenses.

Copied Matroska/MPEG4IP/SFIFO/parser/muxer sources within MP42 are retained. They are not upgraded merely by replacing FFmpeg, and no compatible newer drop-in versions were established in this pass. Their maintenance is separate from the newly rebuilt external libraries. This inventory is not a claim of a complete security or redistribution-license audit of all inherited source.
