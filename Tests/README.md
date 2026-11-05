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
