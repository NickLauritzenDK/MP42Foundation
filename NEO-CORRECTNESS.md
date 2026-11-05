# Neo audio correctness follow-up — 6 November 2026

ALAC importer configurations contain24 bytes; FFmpeg requires a36-byte alac fullbox. The decoder now wraps only the24-byte ALAC configuration and zeroes FFmpeg input padding. Existing36-byte configurations remain accepted; a23-byte malformed configuration remains rejected. Importer/muxer cookie representation is unchanged.

ALAC sample-entry channel count may remain2 for mono or multichannel files. MP42AudioTrack now uses the validated24-byte ALACSpecificConfig channel field and derives the matching default channel layout.

New AAC encoder priming is now applied to copied presentation edits only for lossless PCM/ALAC input through AVFoundation/MP4 importers. Existing empty edits and nonempty edit durations are retained; media offsets are converted to output timebase before adding actual finalized encoder leadingFrames. A source without edits gets a presentation edit using source duration. Other source codecs/importers retain their previous policy. In particular Matroska timing remains a separate audit item: its cleanup constructs different duration metadata, and was not changed without a dedicated fixture.

Verification uses the actual built framework in the parent app's Tests/audio-formats.py/.m:36 PCM/ALAC/AAC conversions (mono,stereo,5.1 at32/44.1/48kHz), two edited ALAC timelines (+250/-100ms) through AVFoundation, and direct24/36/invalid23-byte decoder configuration checks. All38 conversions/timelines and3 decoder checks pass. ALAC source validity was independently checked by byte-identical Apple decoder output. Original failures and tests were observed before fixes. PCM->AAC onset formerly44.9ms late at44.1kHz now passes independent15ms onset/end bounds. Full existing targeted framework regression runners pass on arm64.

This is synthetic short-media coverage, not full listening/AV-sync/surround hardware certification or validation of all formats and OS versions. Source reference: FFmpeg libavcodec/alac.c documents the36-byte input contract. The app's docs/NEO-QUEUE-AUDIO-REVIEW.md carries the full user-facing report.
