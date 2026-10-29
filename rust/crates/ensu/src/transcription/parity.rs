use super::*;

use std::collections::BTreeMap;

#[derive(serde::Deserialize)]
struct ExpectedWord {
    text: String,
    start: f32,
    end: f32,
}
#[derive(serde::Deserialize)]
struct Legacy {
    rate: u32,
    text: String,
    speech_samples: usize,
    speech_sha256: String,
}
#[derive(serde::Deserialize)]
struct Case {
    file: String,
    sha256: String,
    samples: usize,
    text: String,
    words: Vec<ExpectedWord>,
    legacy: Vec<Legacy>,
}
#[derive(serde::Deserialize)]
struct Fixture {
    models: BTreeMap<String, String>,
    vad_sha256: String,
    cases: Vec<Case>,
}

fn checksum(path: &Path) -> String {
    use std::io::Read;
    let mut file = std::fs::File::open(path).unwrap();
    let mut hasher = ente_ensu_crypto::Sha256Hasher::new();
    let mut buffer = vec![0; 64 * 1024];
    loop {
        let length = file.read(&mut buffer).unwrap();
        if length == 0 {
            break;
        }
        hasher.update(&buffer[..length]);
    }
    hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn check(transcriber: &Transcriber, corpus: &Path, cases: &[Case]) {
    for case in cases {
        let path = corpus.join(&case.file);
        assert_eq!(checksum(&path), case.sha256, "{} input", case.file);
        let pcm = std::fs::read(path).unwrap();
        let samples = super::super::audio::pcm16_samples(&pcm).unwrap();
        assert_eq!(samples.len(), case.samples);
        let result = transcriber
            .lock()
            .as_mut()
            .unwrap()
            .transcribe(&samples)
            .unwrap();
        assert_eq!(result.text, case.text, "{} text", case.file);
        assert_eq!(result.words.len(), case.words.len(), "{} words", case.file);
        for (actual, expected) in result.words.iter().zip(&case.words) {
            assert_eq!(actual.text, expected.text, "{} word", case.file);
            assert_eq!(
                actual.start, expected.start,
                "{} {} start",
                case.file, expected.text
            );
            assert_eq!(
                actual.end, expected.end,
                "{} {} end",
                case.file, expected.text
            );
        }
        let aligned = if samples.len() <= crate::voice::MAX_WINDOW_SAMPLES {
            transcriber.transcribe_window(&samples, || false).unwrap()
        } else {
            transcriber.transcribe_tail(&pcm, || false).unwrap()
        };
        assert_eq!(
            aligned.len(),
            case.words.len(),
            "{} aligned words",
            case.file
        );
        for (actual, expected) in aligned.iter().zip(&case.words) {
            assert_eq!(actual.text, expected.text, "{} aligned text", case.file);
            assert_eq!(
                actual.start,
                (expected.start.max(0.0) * 16000.0).round() as u64,
                "{} aligned start",
                case.file
            );
            assert_eq!(
                actual.end,
                ((expected.end.max(0.0) * 16000.0).round() as u64).min(samples.len() as u64),
                "{} aligned end",
                case.file
            );
        }
    }
}

fn check_legacy(transcriber: &Transcriber, corpus: &Path, vad: &Path, cases: &[Case]) {
    for case in cases {
        let pcm = std::fs::read(corpus.join(&case.file)).unwrap();
        let input: Vec<_> = pcm
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| i16::from_le_bytes(*pair))
            .collect();
        for expected in &case.legacy {
            let rate = expected.rate as usize;
            let length = input.len() * rate / 16000;
            let bytes: Vec<_> = (0..length)
                .flat_map(|index| input[index * 16000 / rate].to_le_bytes())
                .collect();
            let speech =
                super::super::audio::extract_speech_from_pcm16(vad, expected.rate, &bytes).unwrap();
            assert_eq!(
                speech.len(),
                expected.speech_samples,
                "{} {} Hz speech",
                case.file,
                rate
            );
            let floats: Vec<_> = speech
                .iter()
                .flat_map(|sample| sample.to_le_bytes())
                .collect();
            let hash: String = ente_ensu_crypto::sha256(&floats)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect();
            assert_eq!(
                hash, expected.speech_sha256,
                "{} {} Hz samples",
                case.file, rate
            );
            assert_eq!(
                transcriber.transcribe(expected.rate, &bytes).unwrap(),
                expected.text,
                "{} {} Hz text",
                case.file,
                rate
            );
        }
    }
}

#[test]
#[ignore = "requires ENSU_TEST_TRANSCRIPTION_MODEL, ENSU_TEST_TRANSCRIPTION_CORPUS and ENSU_TEST_VAD_MODEL"]
fn real_model_text_and_word_timestamps_match_reference() {
    let fixture: Fixture =
        serde_json::from_str(include_str!("../../tests/data/parakeet-parity.json")).unwrap();
    let model_dir = PathBuf::from(std::env::var("ENSU_TEST_TRANSCRIPTION_MODEL").unwrap());
    let corpus = PathBuf::from(std::env::var("ENSU_TEST_TRANSCRIPTION_CORPUS").unwrap());
    for (name, expected) in &fixture.models {
        assert_eq!(checksum(&model_dir.join(name)), *expected, "{name} model");
    }
    let vad = PathBuf::from(std::env::var("ENSU_TEST_VAD_MODEL").unwrap());
    assert_eq!(checksum(&vad), fixture.vad_sha256, "Silero model");
    let transcriber = Transcriber::new(&model_dir, &vad);
    transcriber.load_model().unwrap();
    check(&transcriber, &corpus, &fixture.cases);
    check_legacy(&transcriber, &corpus, &vad, &fixture.cases);
    transcriber.unload_model();

    let directory = tempfile::tempdir().unwrap();
    let cache = GraphCache::new(directory.path().to_path_buf(), "test-device".into());
    for cached in [false, true] {
        let model = cache
            .load(&model_dir, ort::info(), true, |plan| {
                match &plan {
                    LoadPlan::Source { save_to } => {
                        assert!(!cached);
                        assert!(save_to.is_some());
                    }
                    LoadPlan::Cached { .. } => assert!(cached),
                }
                load_plan(&model_dir, plan)
            })
            .unwrap();
        *transcriber.lock() = Some(model);
        check(&transcriber, &corpus, &fixture.cases);
        transcriber.unload_model();
    }
}
