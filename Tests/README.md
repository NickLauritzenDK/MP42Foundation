# Official Subler 1.9.5 characterization tests

These tests characterize a replacement for the unavailable MP42Foundation gitlink 4648f9d585b38957a797bdb13632497abdbe4dfe. The source base is bfa477b799ce55716f744638e6dfe3f23d39c5d7. This is not a claim to recover the missing original source.

## Run the whole suite

After initializing contrib and building MP42Foundation or Subler:

```sh
python3 Tests/run-tests.py /path/to/MP42Foundation.framework /path/to/test-output
# An explicit Subler.app is also accepted.
python3 Tests/run-tests.py /path/to/Subler.app /path/to/test-output-intel --arch x86_64
```

The default architecture is the running machine's architecture. x86_64 execution on an Apple Silicon Mac uses Rosetta, not Intel hardware. Build/test outputs must be outside Tests/; the runner compiles executable harnesses, changes only their library load paths and ad-hoc signatures, and writes synthetic MP4 files to the supplied output directory. It never modifies the supplied app/framework or user media.

## What is covered

- `baseline-tests.m`: 14 explicit checks for insertion, movement, deletion/undo/redo, Unicode/languages, chapters and metadata.
- `track-editing.m`: 440 traces of insertion, selections in both orders, moving up/down/no-op, references and two undo/redo cycles.
- `track-state.m`: 14 traces of indexed moves, imported/muxed state, mixed edits, empty selections, chapter replacement and chapter ordering.
- `media-roundtrip.m`: five actual file workflows: create/reopen a file with two AAC tracks, SRT subtitles, chapters and Unicode metadata; delete/undo/save; delete/undo/redo/save; move/undo/save; move/undo/redo/save. Compares track metadata, timings and SHA-256 of all encoded sample payloads with official-release output.

The gzip JSON files are deterministic golden traces generated against the checksum-verified official 1.9.5 framework. They are external reference behavior, not expectations derived from the replacement implementation. The runner can record missing references only with a framework matching `reference-provenance.json`, and refuses to overwrite an existing different trace.

19 reverse-ordered removal traces catch **existing official NSRangeException outcomes**. They do not represent successful undo operations or newly fixed bugs. Preserving them avoids folding an unrelated behavior change into source recovery. Chapter replacement also inherits the official limitation that undo does not restore a replaced old chapter track.

The original available framework fails the release-API guard before the repair. An initial repair passed the 440 cases but failed seven state scenarios; the final repair passes those as well. Both architecture slices of the app build; all tests passed on arm64 and x86_64 under Rosetta on 2026-11-05. Independent review reran the arm64 suite with no actionable findings.

## Synthetic audio fixture

`fixtures/tone.m4a` contains a generated 0.5-second, mono 48 kHz, 440 Hz tone, amplitude 7000 in 16-bit PCM before encoding. It was encoded with Apple's `afconvert -f m4af -d aac -b 128000`. It contains no user/copyrighted media. The fixed fixture checksum and official framework/ZIP provenance are in `reference-provenance.json`. AAC encoder output may vary across macOS versions, so tests use the checked-in fixture rather than regenerating it on every run.

## Limits

This is targeted characterization, not proof of complete UI or feature parity. It does not cover every codec, malformed input, real PGS/VobSub OCR, artwork, queue/AppleScript/network services, updater installation, old macOS versions, native Intel hardware, or explicitly disabled undo registration. The Subler source and interface resources remain unchanged in the source-recovery phase. Latest dependency upgrades are a separate incremental step.

## Component modernization checks

- `test-source-verification.py`: corrupted archive rejection and regression cases proving modified extracted/patched caches cannot replace pinned source. The original builder fails both cache cases; the corrected builder passes all three checks.
- `run-ocr-test.py APP OUTPUT [--arch x86_64]`: reads runtime Tesseract/Leptonica versions from the actual framework and invokes the unchanged app OCR wrapper with its original English traineddata on generated text for English and the existing undefined-language fallback. An installed legacy English model is used when present; the fallback path uses bundled English when no undefined-language model is installed. It checks functionality, not improved accuracy on a user corpus.
- `image-codecs.c`: the builder links this probe against explicit generated static archives and verifies PNG/TIFF lossless roundtrips plus JPEG encode/decode. The upstream PNG/JPEG/TIFF suites are also run separately for each architecture.
- `run-ffmpeg-test.py APP OUTPUT --include DEPENDENCIES/ffmpeg/include`: first links **only** the actual framework, checking libavcodec 63.1.102 (FFmpeg 9.0.2), its 32 decoder registrations, AC3 encoder, 3 parsers and a decoded synthetic PGS bitmap. A second executable links the dependency archives without the framework, checking the full configured matrix, resampler and Opus muxer. Those latter unused APIs are not claimed to exist in the shipped app binary.
- `run-audio-test.py APP OUTPUT [--arch x86_64]`: invokes actual app AAC/AC3 conversion, saves/reopens metadata and decodes the generated media through macOS AudioToolbox. Timing/channel/rate/frame count/metadata must match the official baseline. Decoded signed-16-bit PCM may differ by at most 0.1% relative RMS; measured differences are printed, not called bit-identical. This uses a short fixed synthetic AAC input and does not establish multichannel/all-codec parity.
- `mp4v2-director.c`: standalone source-built MP4v2 create/store/reopen with Unicode Director metadata, verifying the API already required by Subler's original writer.

The original release's OCR and FFmpeg tests pass in `--allow-old` characterization mode and fail their new runtime-version assertions before the upgrade. Official audio reference recording is guarded by the original framework hash. The 454 original editing/state traces and 5 original media workflows remain frozen; modernization must not bless candidate output as a new reference.

## Audio correctness regressions

`python3 Tests/run-audio-correctness-test.py /path/to/MP42Foundation.framework /path/to/output`
uses generated stereo PCM at 22.05, 24, 32, 44.1, 48 and 96 kHz through the real import/conversion/mux/reopen path. It checks duration (70 ms tolerance for packet/codec framing), a 440 Hz tone (4 Hz zero-crossing tolerance), 48 kHz output and MP4 timebase, and a silent tail. A direct AC3 encoder probe checks that a partial last input frame pads with silence rather than reusing old PCM. A direct decoder probe verifies that one second of 96 kHz PCM produces exactly 48,000 frames after draining the resampler. It also checks cancellation of idle AC3/AAC encoder and decoder workers, with a process timeout to catch a blocked join. macOS audio codec access is required; restricted processes may produce AudioToolbox `fmt?` errors.

The independent C resampler probe can be built with the generated FFmpeg dependencies:

```sh
xcrun clang -IMP42/muxer -I/path/to/ffmpeg/include Tests/audio-resample.c MP42/muxer/audio_resample.c /path/to/ffmpeg/lib/libswresample.a /path/to/ffmpeg/lib/libavutil.a -framework Accelerate -o /path/to/output/audio-resample
/path/to/output/audio-resample
```

It verifies rate-only stereo float conversion from 96 to 48 kHz, including the delayed output flushed at EOF. These are correctness assertions separate from the frozen official-release audio characterization; they do not replace or regenerate its golden data. The production AC3 encoder retains its existing 48 kHz output policy and now converts input samples to that rate.

Saving/error regressions: `python3 Tests/run-save-failures.py APP_OR_FRAMEWORK OUTPUT [--arch arm64|x86_64]` exercises missing-source protection, relinking/retry, track-write error propagation and partial setup cancellation/retry. AudioToolbox requires a normal developer session.

FIFO regressions: `python3 Tests/run-fifo-test.py APP_OR_FRAMEWORK OUTPUT [--arch arm64|x86_64]` compiles the actual non-ARC queue source, covering blocking readers/writers, cancellation, retained ownership, ordering and multiple concurrent producers/readers.

`run-audio-correctness-test.py` also accepts an app bundle, `--arch` and `--dependencies PATH`; it tests the actual framework plus the separately compiled production resampler.
