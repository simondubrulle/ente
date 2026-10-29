# Parakeet compatibility tests

The transcription backend is implemented independently using the shipped ONNX graph signatures, NVIDIA's [transducer description](https://arxiv.org/abs/2304.06795), and black-box reference outputs. No implementation code was copied from transcribe-rs.

The compatibility decoder advances one encoder frame on a blank prediction and permits up to ten symbols per frame. It does not use the five duration logits for frame skipping: doing so changes the pinned backend's text and word timestamps. The 250 ms leading silence, 80 ms encoder frames, SentencePiece word grouping, final 50 ms token span, and removal of the leading timestamp offset preserve the existing behavior. VAD prefill uses rolling history, including overlap with previously emitted hangover frames.

`data/parakeet-parity.json` contains outputs captured through the public API of transcribe-rs revision `efc66111d519a434e28d51d94740008a7ce29360`, using `ort` 2.0.0-rc.13 and its bundled ONNX Runtime 1.28.0 on CPU. It checks compatibility with that revision, including its recognition errors; it is not a ground-truth accuracy benchmark.

The corpus has 14 cases and 150 reference words: JFK's full recording, overlapping windows, a short prefix, added silence, seven LibriSpeech excerpts, silence, and a single sample. Input checksums and hashes of all four Parakeet files and the Silero model are checked before inference. The model test requires exact text, word count, word text, and `f32` start/end equality. It also checks Ensu's live/recorded sample alignment, and repeats the corpus with source graphs, newly serialized optimized graphs, and reused cached graphs. Parakeet sessions are reused between cases; recurrent decoder state is initialized for every transcription.

The same opt-in test checks the full legacy PCM → resampler → Silero VAD → Parakeet path against 42 reference results: each input at 16, 44.1, and 48 kHz. It constructs the higher-rate inputs by repeating source samples at the corresponding indices. After speech extraction, both the sample count and the SHA-256 of little-endian `f32` samples must match before the public `Transcriber::transcribe` text is compared. This covers the production VAD smoothing settings and resampling with actual models.

Only reference outputs and hashes are committed. Audio is fetched from pinned revisions of the [whisper.cpp JFK sample](https://github.com/ggerganov/whisper.cpp/blob/284029c07012d2000941a08d38a31ffb71f4734e/samples/jfk.wav) and [LibriSpeech dummy dataset](https://huggingface.co/datasets/hf-internal-testing/librispeech_asr_dummy/tree/5be91486e11a2d616f4ec5db8d3fd248585ac07a). The preparation script verifies both recordings before deriving PCM16 mono inputs at 16 kHz, and downloads the checksum-verified Silero model.

## Run

The recorded platform is macOS arm64 with Rust 1.99.0. Install that toolchain and `uv`, and mount an external scratch volume before starting. The example below uses `/Volumes/DevScratch`; adjust that path for your setup. Start in the repository's `rust/` directory and make a disposable external copy so the original checkout stays free of build outputs:

```sh
scratch_dir="/Volumes/DevScratch/ensu-transcription-parity"
mkdir -p "$scratch_dir/workspace/rust" "$scratch_dir/tmp" "$scratch_dir/models"
rsync -a --exclude target --exclude .git --exclude node_modules ./ "$scratch_dir/workspace/rust/"
export TMPDIR="$scratch_dir/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
export CARGO_TARGET_DIR="$scratch_dir/target"
export CARGO_BUILD_BUILD_DIR="$scratch_dir/build"
cd "$scratch_dir/workspace/rust"
```

Cargo compilation outputs and tempfile-created optimized graphs now go to scratch. These commands reuse your existing package caches and ort's runtime-binary download cache under their normal configuration; they do not relocate those shared caches.

Download [Ensu's model archive](https://models.ente.com/parakeet-v3-int8.tar.gz), verify SHA-256 `43d37191602727524a7d8c6da0eef11c4ba24320f5b4730f1a2497befc2efa77`, and extract it into `$scratch_dir/models`. The archive contains a `parakeet-tdt-0.6b-v3-int8` directory. Then prepare and run:

```sh
export ENSU_TEST_TRANSCRIPTION_MODEL="$scratch_dir/models/parakeet-tdt-0.6b-v3-int8"
uv run --no-project --with pyarrow==26.0.0 --with soundfile==0.14.0 \
  python crates/ensu/tests/prepare_transcription_fixtures.py "$scratch_dir/corpus"
export ENSU_TEST_TRANSCRIPTION_CORPUS="$scratch_dir/corpus/pcm"
export ENSU_TEST_VAD_MODEL="$scratch_dir/corpus/silero_vad_v4.onnx"
cargo +1.99 test --locked -p ente-ensu --features transcription --lib \
  real_model_text_and_word_timestamps_match_reference -- --ignored --nocapture
```

The test is ignored by default so ordinary unit tests need neither downloads nor model inference. Use the same runtime and platform as the reference: changing them can change recognition or resampler fingerprints even with identical model files. These checks do not establish physical-device behavior or exhaust the model's supported languages.

## Regenerate reference outputs

Keep the reference dependency in a separate disposable Cargo project outside this workspace. Pin the Git revision above and enable only `onnx`. Pin `ort` and `ort-sys` to `=2.0.0-rc.13` to keep the runtime binding identical. For each prepared `.pcm` file, call:

```rust
use transcribe_rs::onnx::{
    Quantization,
    parakeet::{ParakeetModel, ParakeetParams, TimestampGranularity},
};

let mut model = ParakeetModel::load(model_directory, &Quantization::Int8)?;
let samples: Vec<f32> = pcm.chunks_exact(2)
    .map(|pair| i16::from_le_bytes([pair[0], pair[1]]) as f32 / 32768.0)
    .collect();
let result = model.transcribe_with(&samples, &ParakeetParams {
    timestamp_granularity: Some(TimestampGranularity::Word),
    ..Default::default()
})?;
```

Record `result.text` and every segment's `text`, `start`, and `end`, together with the PCM sample count and SHA-256. Retain the model hashes and reference revision in the fixture. Do not add the reference crate back to the workspace or its development dependencies.

The legacy results were captured from Ensu commit `717d7444c1d75d4fe41d68d31f456959d01c50f2`, whose adapter uses the same pinned dependency. For each source input and rate, construct PCM with the index rule in `parity.rs`, capture the public `Transcriber::transcribe` result, and instrument `extract_speech_from_pcm16` in a disposable copy to capture its sample count and `f32` checksum. Keep the same Silero file, model files, platform, and runtime for reference and replacement.
