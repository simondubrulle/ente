use std::collections::VecDeque;

use super::{
    AudioRing, MAX_WINDOW_SAMPLES, Result, VOICE_SAMPLE_RATE, VoiceError, transcript_separator,
};

const PRE_SPEECH: u64 = VOICE_SAMPLE_RATE;
const PHRASE_SILENCE: u64 = VOICE_SAMPLE_RATE * 3;
const LOOKBACK: u64 = VOICE_SAMPLE_RATE * 3 / 2;
const UPDATE_SAMPLES: u64 = VOICE_SAMPLE_RATE / 2;
const ALIGNMENT_TOLERANCE: u64 = VOICE_SAMPLE_RATE / 5;
const REQUIRED_OBSERVATIONS: u8 = 3;
const RIGHT_CONTEXT_WORDS: usize = 2;

#[derive(Clone, Debug)]
pub(crate) struct AlignedWord {
    pub text: String,
    pub start: u64,
    pub end: u64,
}

pub(crate) struct DecodeWindow {
    pub id: u64,
    pub start: u64,
    pub end: u64,
    pub final_phrase: bool,
    pub samples: Vec<f32>,
}

#[derive(Debug)]
pub(crate) struct RecognitionUpdate {
    pub commit: Option<(u64, u64, String)>,
    pub hypothesis: String,
    pub covered_through: u64,
}

struct Region {
    start: u64,
    last_voice: u64,
    end: Option<u64>,
}

#[derive(Default)]
pub(crate) struct RollingRecognizer {
    ring: AudioRing,
    regions: VecDeque<Region>,
    previous: Vec<AlignedWord>,
    observations: Vec<u8>,
    anchor: Option<AlignedWord>,
    covered: u64,
    last_decoded: u64,
    next_id: u64,
    in_flight: Option<(u64, u64, u64, bool)>,
}

impl RollingRecognizer {
    pub fn feed(&mut self, samples: &[f32], voiced: bool) -> Result<()> {
        if samples.is_empty() {
            return Err(VoiceError::InvalidAudio("Audio buffer is empty".into()));
        }
        let start = self.ring.accepted();
        self.ring.push(start, samples)?;
        let end = self.ring.accepted();
        if voiced {
            if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none()) {
                region.last_voice = end;
            } else {
                let prior_end = self
                    .regions
                    .back()
                    .and_then(|r| r.end)
                    .unwrap_or(self.covered);
                self.regions.push_back(Region {
                    start: start
                        .saturating_sub(PRE_SPEECH)
                        .max(self.ring.retained_from())
                        .max(prior_end),
                    last_voice: end,
                    end: None,
                });
            }
        } else if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none())
            && end - region.last_voice >= PHRASE_SILENCE
        {
            region.end = Some(end);
        }
        self.release_silence()?;
        Ok(())
    }

    fn release_silence(&mut self) -> Result<()> {
        if self.regions.is_empty() {
            let end = self.ring.accepted();
            self.ring.acknowledge(
                end,
                end.saturating_sub(PRE_SPEECH)
                    .max(self.ring.retained_from()),
            )?;
            self.covered = self.covered.max(self.ring.retained_from());
        }
        Ok(())
    }

    pub fn finish(&mut self) {
        if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none()) {
            region.end = Some(self.ring.accepted());
        }
    }

    pub fn next_window(&mut self) -> Result<Option<DecodeWindow>> {
        if self.in_flight.is_some() {
            return Ok(None);
        }
        let Some(region) = self.regions.front() else {
            return Ok(None);
        };
        let end = region
            .end
            .unwrap_or(self.ring.accepted())
            .min(region.start + MAX_WINDOW_SAMPLES as u64);
        let final_phrase = region.end == Some(end);
        let at_limit = end - region.start == MAX_WINDOW_SAMPLES as u64;
        if !final_phrase
            && !at_limit
            && (end - region.start < UPDATE_SAMPLES || end < self.last_decoded + UPDATE_SAMPLES)
        {
            return Ok(None);
        }
        self.next_id += 1;
        self.in_flight = Some((self.next_id, region.start, end, final_phrase));
        Ok(Some(DecodeWindow {
            id: self.next_id,
            start: region.start,
            end,
            final_phrase,
            samples: self.ring.window(region.start, end)?,
        }))
    }

    pub fn complete(
        &mut self,
        request: &DecodeWindow,
        words: Vec<AlignedWord>,
    ) -> Result<RecognitionUpdate> {
        if self.in_flight != Some((request.id, request.start, request.end, request.final_phrase)) {
            return Err(VoiceError::StaleEvent);
        }
        let mut current = words;
        let mut previous_start = 0;
        for word in &mut current {
            if word.text.trim().is_empty()
                || word.start < previous_start
                || word.end < word.start
                || word.end > request.end - request.start
            {
                return Err(VoiceError::UnstableTranscript);
            }
            previous_start = word.start;
            word.start += request.start;
            word.end += request.start;
        }
        let skip = self.overlap_end(&current)?;
        let remaining = &current[skip..];
        let old_skip = self.overlap_end(&self.previous)?;
        let mut observations = vec![1; current.len()];
        let agreed_prefix = remaining
            .iter()
            .zip(&self.previous[old_skip..])
            .take_while(|(a, b)| {
                a.text == b.text && a.start.abs_diff(b.start) <= ALIGNMENT_TOLERANCE
            })
            .count();
        for i in 0..agreed_prefix {
            observations[skip + i] = self.observations[old_skip + i].saturating_add(1);
        }
        let mature = observations[skip..]
            .iter()
            .take_while(|count| **count >= REQUIRED_OBSERVATIONS)
            .count()
            .saturating_sub(RIGHT_CONTEXT_WORDS);
        let agreed = remaining
            .iter()
            .take(mature)
            .take_while(|word| word.end <= request.end.saturating_sub(LOOKBACK))
            .count();
        let commit_count = if request.final_phrase {
            remaining.len()
        } else {
            agreed
        };
        if request.final_phrase && current.is_empty() {
            return Err(VoiceError::IncompleteAudio);
        }
        let commit = if commit_count > 0 {
            let end = if request.final_phrase {
                request.end
            } else {
                remaining[commit_count - 1].end
            };
            if end <= self.covered {
                return Err(VoiceError::UnstableTranscript);
            }
            let text = join_words(&remaining[..commit_count]);
            let start = self.covered.max(request.start);
            self.covered = end;
            self.anchor = Some(remaining[commit_count - 1].clone());
            Some((start, end, text))
        } else {
            None
        };
        let hypothesis = join_words(&remaining[commit_count..]);
        self.previous = current;
        self.observations = observations;
        self.last_decoded = request.end;
        self.in_flight = None;
        let mut retain_from = request.start;
        if request.final_phrase {
            self.covered = request.end;
            self.regions.pop_front();
            self.previous.clear();
            self.observations.clear();
            self.anchor = None;
            self.last_decoded = 0;
            retain_from = self.regions.front().map_or(request.end, |r| r.start);
            retain_from = retain_from.min(request.end);
        } else if request.end - request.start == MAX_WINDOW_SAMPLES as u64 {
            if self.covered <= request.start + LOOKBACK {
                return Err(VoiceError::UnstableTranscript);
            }
            retain_from = self
                .covered
                .saturating_sub(LOOKBACK)
                .min(self.anchor.as_ref().map_or(self.covered, |w| w.start))
                .max(request.start);
            if retain_from <= request.start {
                return Err(VoiceError::UnstableTranscript);
            }
            if let Some(region) = self.regions.front_mut() {
                region.start = retain_from;
            }
        }
        self.ring.acknowledge(
            request.end.max(self.ring.processed()),
            retain_from.max(self.ring.retained_from()),
        )?;
        self.release_silence()?;
        Ok(RecognitionUpdate {
            commit,
            hypothesis,
            covered_through: self.covered,
        })
    }

    fn overlap_end(&self, words: &[AlignedWord]) -> Result<usize> {
        let Some(anchor) = &self.anchor else {
            return Ok(0);
        };
        if words.is_empty() {
            return Ok(0);
        }
        let anchor_key = alignment_key(&anchor.text);
        let mut matches = words.iter().enumerate().filter_map(|(i, word)| {
            (alignment_key(&word.text) == anchor_key
                && word.start.abs_diff(anchor.start) <= ALIGNMENT_TOLERANCE)
                .then_some(i + 1)
        });
        match (matches.next(), matches.next()) {
            (Some(end), None) => Ok(end),
            (None, None) if words[0].start >= self.covered => Ok(0),
            _ => Err(VoiceError::UnstableTranscript),
        }
    }

    pub fn is_settled(&self) -> bool {
        self.regions.is_empty() && self.in_flight.is_none()
    }
    #[cfg(test)]
    fn covered(&self) -> u64 {
        self.covered
    }
    #[cfg(test)]
    fn retained_samples(&self) -> usize {
        self.ring.retained_samples()
    }
}

fn alignment_key(text: &str) -> String {
    let lexical = text.trim().trim_matches([
        '.', ',', '!', '?', ':', ';', '…', '。', '，', '！', '？', '؛', '،', '।', '॥', '¿', '¡',
        '"', '“', '”',
    ]);
    if lexical.is_empty() {
        text.trim().to_owned()
    } else {
        lexical.to_lowercase()
    }
}

fn join_words(words: &[AlignedWord]) -> String {
    let mut text = String::new();
    for word in words {
        text.push_str(transcript_separator(&text, &word.text));
        text.push_str(&word.text);
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    fn aligned(text: &str, start: u64, end: u64) -> AlignedWord {
        AlignedWord {
            text: text.into(),
            start,
            end,
        }
    }

    #[test]
    fn provisional_revisions_need_repeated_right_context_before_commit() {
        let mut rolling = RollingRecognizer::default();
        for index in 0..5 {
            rolling.feed(&vec![0.1; 8000], true).unwrap();
            let request = rolling.next_window().unwrap().unwrap();
            let first = if index < 2 { "Friday" } else { "Saturday" };
            let update = rolling
                .complete(
                    &request,
                    vec![
                        aligned(first, 0, 1000),
                        aligned("at", 1000, 2000),
                        aligned("noon", 2000, 3000),
                    ],
                )
                .unwrap();
            if index < 4 {
                assert!(update.commit.is_none());
                assert_eq!(update.hypothesis, format!("{first} at noon"));
            } else {
                assert_eq!(update.commit.unwrap().2, "Saturday");
                assert_eq!(update.hypothesis, "at noon");
            }
        }
    }

    #[test]
    fn repeated_unfinished_tail_stays_revisable_until_endpoint() {
        let mut rolling = RollingRecognizer::default();
        for _ in 0..6 {
            rolling.feed(&vec![0.1; 8000], true).unwrap();
            let request = rolling.next_window().unwrap().unwrap();
            let update = rolling
                .complete(
                    &request,
                    vec![aligned("This", 0, 1000), aligned("one.", 1000, 2000)],
                )
                .unwrap();
            assert!(update.commit.is_none());
        }
        rolling.finish();
        let request = rolling.next_window().unwrap().unwrap();
        let update = rolling
            .complete(
                &request,
                vec![aligned("And", 0, 1000), aligned("so", 1000, 2000)],
            )
            .unwrap();
        assert_eq!(update.commit.unwrap().2, "And so");
        assert!(rolling.is_settled());
    }

    #[test]
    fn short_vad_dropout_preserves_contiguous_audio_and_phrase() {
        let mut rolling = RollingRecognizer::default();
        rolling.feed(&vec![0.1; 8000], false).unwrap();
        rolling.feed(&vec![0.2; 8000], true).unwrap();
        rolling.feed(&vec![0.3; 16000], false).unwrap();
        rolling.feed(&vec![0.4; 8000], true).unwrap();
        let request = rolling.next_window().unwrap().unwrap();
        assert_eq!((request.start, request.end), (0, 40000));
        assert!(!request.final_phrase);
        assert_eq!(&request.samples[16000..32000], &vec![0.3; 16000]);
        assert_eq!(rolling.regions.len(), 1);
    }

    #[test]
    fn overlap_ignores_boundary_punctuation_but_preserves_acoustic_identity() {
        let rolling = RollingRecognizer {
            anchor: Some(aligned("You.", 16000, 20000)),
            covered: 20000,
            ..RollingRecognizer::default()
        };
        assert_eq!(
            rolling.overlap_end(&[aligned("you,", 16000, 20000), aligned("you", 22000, 26000)]),
            Ok(1)
        );
        assert_eq!(
            rolling.overlap_end(&[aligned("you", 16000, 18000), aligned("you", 18000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(
            rolling.overlap_end(&[aligned("you", 12000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(
            rolling.overlap_end(&[aligned("not", 16000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_ne!(alignment_key("don't"), alignment_key("do"));
        assert_ne!(alignment_key("कि"), alignment_key("क"));
        assert_ne!(alignment_key("-5"), alignment_key("5"));
        let rolling = RollingRecognizer {
            anchor: Some(aligned("Café!", 16000, 20000)),
            covered: 20000,
            ..RollingRecognizer::default()
        };
        assert_eq!(rolling.overlap_end(&[aligned("café", 16000, 20000)]), Ok(1));
        assert_eq!(
            rolling.overlap_end(&[aligned("cafe\u{301}", 16000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
    }

    fn words(request: &DecodeWindow) -> Vec<AlignedWord> {
        (0..request.end / 4000)
            .filter_map(|i| {
                let start = i * 4000;
                (start >= request.start).then(|| AlignedWord {
                    text: "no".into(),
                    start: start - request.start,
                    end: (start + 3000).min(request.end) - request.start,
                })
            })
            .collect()
    }

    #[test]
    fn continuous_speech_advances_stable_text_without_losing_repetitions() {
        let mut rolling = RollingRecognizer::default();
        let mut committed = String::new();
        for _ in 0..7200 {
            rolling.feed(&vec![0.2; 4000], true).unwrap();
            if let Some(request) = rolling.next_window().unwrap() {
                assert!(request.samples.len() <= MAX_WINDOW_SAMPLES);
                let update = rolling.complete(&request, words(&request)).unwrap();
                if let Some((_, _, text)) = update.commit {
                    committed.push_str(&text);
                    committed.push(' ');
                }
            }
            assert!(rolling.retained_samples() <= 30 * 16000);
        }
        assert!(committed.split_whitespace().count() > 7100);
        rolling.finish();
        while let Some(request) = rolling.next_window().unwrap() {
            if let Some((_, _, text)) = rolling.complete(&request, words(&request)).unwrap().commit
            {
                committed.push_str(&text);
                committed.push(' ');
            }
        }
        assert!(rolling.is_settled());
        assert_eq!(committed.split_whitespace().count(), 7200);
    }

    #[test]
    fn final_short_speech_and_stale_results_are_handled() {
        let mut rolling = RollingRecognizer::default();
        rolling.feed(&vec![0.1; 3200], true).unwrap();
        assert!(rolling.next_window().unwrap().is_none());
        rolling.finish();
        let request = rolling.next_window().unwrap().unwrap();
        let update = rolling
            .complete(
                &request,
                vec![AlignedWord {
                    text: "Ha".into(),
                    start: 0,
                    end: 3200,
                }],
            )
            .unwrap();
        assert_eq!(update.commit.unwrap().2, "Ha");
        assert!(matches!(
            rolling.complete(&request, Vec::new()),
            Err(VoiceError::StaleEvent)
        ));
    }

    #[test]
    fn failed_alignment_keeps_audio_and_does_not_claim_completion() {
        let mut rolling = RollingRecognizer::default();
        rolling.feed(&vec![0.1; 8000], true).unwrap();
        let request = rolling.next_window().unwrap().unwrap();
        assert!(
            rolling
                .complete(
                    &request,
                    vec![AlignedWord {
                        text: "bad".into(),
                        start: 0,
                        end: 9000
                    }]
                )
                .is_err()
        );
        assert_eq!(rolling.retained_samples(), 8000);
        assert_eq!(rolling.covered(), 0);
    }
}
