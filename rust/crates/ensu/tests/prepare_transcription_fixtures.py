import argparse
import hashlib
import io
import urllib.request
import wave
from pathlib import Path

import pyarrow.parquet as pq
import soundfile


def download(directory, name, url, checksum):
    path = directory / name
    cached = path.exists()
    if cached:
        data = path.read_bytes()
    else:
        request = urllib.request.Request(
            url, headers={"User-Agent": "ente-transcription-parity/1.0"}
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    if hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError(f"Checksum mismatch: {path}")
    if not cached:
        path.write_bytes(data)
    return path


def prepare(directory):
    directory.mkdir(parents=True, exist_ok=True)
    download(
        directory,
        "silero_vad_v4.onnx",
        "https://models.ente.com/silero_vad_v4.onnx",
        "a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28",
    )
    jfk = download(
        directory,
        "jfk.wav",
        "https://raw.githubusercontent.com/ggerganov/whisper.cpp/284029c07012d2000941a08d38a31ffb71f4734e/samples/jfk.wav",
        "59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e",
    )
    librispeech = download(
        directory,
        "librispeech.parquet",
        "https://huggingface.co/datasets/hf-internal-testing/librispeech_asr_dummy/resolve/5be91486e11a2d616f4ec5db8d3fd248585ac07a/clean/validation-00000-of-00001.parquet",
        "4e69a06fa5edc90921e5e7e39a7084881f8b3ed9c805c574f4f39c6fde27c603",
    )
    with wave.open(str(jfk)) as recording:
        assert recording.getnchannels() == 1
        assert recording.getsampwidth() == 2
        assert recording.getframerate() == 16000
        speech = recording.readframes(recording.getnframes())
    cases = {
        "jfk_full": speech,
        "jfk_opening": speech[: 8 * 32000],
        "jfk_overlap": speech[4 * 32000 :],
        "jfk_short": speech[:25600],
        "jfk_padded": bytes(16000) + speech[: 5 * 32000] + bytes(16000),
        "silence": bytes(32000),
        "single_sample": bytes(2),
    }
    table = pq.read_table(librispeech)
    for index in [0, 1, 10, 20, 40, 60, 72]:
        row = table.slice(index, 1).to_pylist()[0]
        samples, rate = soundfile.read(io.BytesIO(row["audio"]["bytes"]), dtype="int16")
        assert rate == 16000 and samples.ndim == 1
        cases[f"librispeech_{row['id']}"] = samples.astype("<i2").tobytes()
    corpus = directory / "pcm"
    corpus.mkdir(exist_ok=True)
    for name, pcm in cases.items():
        (corpus / f"{name}.pcm").write_bytes(pcm)
    print(corpus)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    prepare(parser.parse_args().directory)
