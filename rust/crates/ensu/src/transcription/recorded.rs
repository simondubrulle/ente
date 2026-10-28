use std::time::Duration;

use transcribe_rs::vad::Vad;

use super::{LiveControl, LiveEvent, LiveTranscription, StreamNormalizer, Transcriber};
use crate::voice::{Result, VoiceError};

const MAX_RECORDED_SAMPLES: usize = (30 * 60 + 2) * 16_000;

pub(super) fn transcribe_chunks(
    mut samples: &[f32],
    mut decode: impl FnMut(&[f32]) -> super::Result<Option<String>>,
) -> super::Result<Option<String>> {
    use crate::voice::{MAX_WINDOW_SAMPLES, VOICE_SAMPLE_RATE, transcript_separator};

    let mut text = String::new();
    while !samples.is_empty() {
        let end = if samples.len() <= MAX_WINDOW_SAMPLES {
            samples.len()
        } else {
            let limit = MAX_WINDOW_SAMPLES.min(samples.len() - VOICE_SAMPLE_RATE as usize);
            let start = limit - 2 * VOICE_SAMPLE_RATE as usize;
            let offset = samples[start..limit]
                .as_chunks::<{ super::VAD_FRAME_SAMPLES }>()
                .0
                .iter()
                .enumerate()
                .map(|(index, frame)| {
                    (
                        index,
                        frame.iter().map(|sample| sample * sample).sum::<f32>(),
                    )
                })
                .min_by(|a, b| a.1.total_cmp(&b.1))
                .map_or(0, |(index, _)| (index + 1) * super::VAD_FRAME_SAMPLES);
            start + offset
        };
        let Some(chunk) = decode(&samples[..end])? else {
            return Ok(None);
        };
        let chunk = chunk.trim();
        text.push_str(transcript_separator(&text, chunk));
        text.push_str(chunk);
        samples = &samples[end..];
    }
    Ok(Some(text))
}

#[derive(Default)]
pub(super) struct RecordedPcm(Vec<u8>);

impl RecordedPcm {
    pub fn push(&mut self, samples: &[f32]) -> Result<()> {
        if samples.len() > MAX_RECORDED_SAMPLES.saturating_sub(self.0.len() / 2) {
            return Err(VoiceError::BacklogFull);
        }
        self.0.extend(samples.iter().flat_map(|sample| {
            ((sample * 32768.0).round().clamp(-32768.0, 32767.0) as i16).to_le_bytes()
        }));
        Ok(())
    }

    pub fn bytes(&self) -> &[u8] {
        &self.0
    }
}

impl Drop for RecordedPcm {
    fn drop(&mut self) {
        use zeroize::Zeroize;
        self.0.zeroize();
    }
}

impl LiveTranscription {
    pub fn run_recorded(
        &self,
        transcriber: &Transcriber,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        self.run_recorded_with(
            || transcriber.live_vad(),
            |pcm| transcriber.transcribe_recording(pcm, || self.queue.is_cancelled()),
            on_event,
        )
    }

    fn run_recorded_with(
        &self,
        make_vad: impl FnOnce() -> Result<Box<dyn Vad>>,
        decode: impl FnOnce(&[u8]) -> Result<String>,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        let _capture = self.start()?;
        let mut vad = make_vad()?;
        let mut normalizer = StreamNormalizer::new(self.queue.format())?;
        self.emit(LiveEvent::Ready, on_event)?;
        let mut pcm = RecordedPcm::default();
        let mut accepted = 0_u64;
        let mut heard_speech = false;
        let mut notified_stop = false;
        loop {
            self.check()?;
            let chunk = self.queue.take();
            let had_chunk = chunk.is_some();
            let mut emit = |frame: &[f32], real: usize| -> Result<()> {
                let voiced = vad.is_speech(frame).map_err(|error| {
                    super::voice_error("Detect speech in recorded audio", error)
                })?;
                heard_speech |= voiced;
                let start = accepted;
                accepted += real as u64;
                self.emit(
                    LiveEvent::Audio {
                        start,
                        end: accepted,
                        voiced,
                    },
                    on_event,
                )?;
                pcm.push(&frame[..real])
            };
            if let Some(chunk) = chunk {
                normalizer.push(&chunk, &mut emit)?;
            }
            let drained = self.queue.is_drained();
            if drained {
                normalizer.finish(&mut emit)?;
            }
            if self.queue.is_closed() && !notified_stop {
                self.emit(LiveEvent::CaptureClosed, on_event)?;
                notified_stop = true;
            }
            if drained {
                break;
            }
            if !had_chunk {
                self.emit(LiveEvent::Idle, on_event)?;
                std::thread::sleep(Duration::from_millis(10));
            }
        }
        drop(vad);
        drop(normalizer);
        self.check()?;
        if heard_speech {
            let text = decode(pcm.bytes())?;
            self.check()?;
            if !text.trim().is_empty() {
                self.emit(LiveEvent::ReplaceTranscript(text), on_event)?;
            }
        }
        self.emit(LiveEvent::Coverage(accepted), on_event)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::voice::CaptureFormat;
    use transcribe_rs::vad::EnergyVad;

    #[test]
    fn recorded_decoding_bounds_windows_preserves_tails_and_stops_on_cancel() {
        use crate::voice::MAX_WINDOW_SAMPLES;

        let mut samples = vec![0.25; MAX_WINDOW_SAMPLES * 3 + 1];
        let quiet = MAX_WINDOW_SAMPLES - 2 * 16000 + 10 * super::super::VAD_FRAME_SAMPLES;
        samples[quiet..quiet + super::super::VAD_FRAME_SAMPLES].fill(0.0);
        let mut offset = 0;
        let mut decoded = 0;
        let text = transcribe_chunks(&samples, |chunk| {
            assert!(chunk.len() <= MAX_WINDOW_SAMPLES);
            assert!(chunk.len() >= 16000);
            assert_eq!(chunk, &samples[offset..offset + chunk.len()]);
            if offset == 0 {
                assert_eq!(chunk.len(), quiet + super::super::VAD_FRAME_SAMPLES);
            }
            offset += chunk.len();
            decoded += 1;
            Ok(Some(" again ".into()))
        })
        .unwrap()
        .unwrap();
        assert_eq!(offset, samples.len());
        assert_eq!(text.split_whitespace().count(), decoded);
        let mut calls = 0;
        assert!(
            transcribe_chunks(&samples, |_| {
                calls += 1;
                Ok((calls == 1).then(|| "unfinished".into()))
            })
            .unwrap()
            .is_none()
        );
        assert_eq!(calls, 2);
    }

    #[test]
    fn recorded_capacity_rejects_a_whole_frame_without_overwriting_audio() {
        let mut pcm = RecordedPcm(vec![0; (MAX_RECORDED_SAMPLES - 1) * 2]);
        pcm.push(&[0.25]).unwrap();
        assert_eq!(pcm.bytes().len(), MAX_RECORDED_SAMPLES * 2);
        assert_eq!(pcm.push(&[0.5]), Err(VoiceError::BacklogFull));
        assert_eq!(
            &pcm.bytes()[pcm.bytes().len() - 2..],
            &8192_i16.to_le_bytes()
        );
    }

    #[test]
    fn recorded_completion_preserves_the_tail_and_cancellation_suppresses_results() {
        for cancelled in [false, true] {
            let stream = LiveTranscription::new(CaptureFormat {
                sample_rate: 16000,
                channels: 1,
            })
            .unwrap();
            stream.feed(&[0, 32].repeat(1001)).unwrap();
            stream.finish();
            let mut closed = 0;
            let mut commits = Vec::new();
            let mut covered = None;
            let result = stream.run_recorded_with(
                || {
                    Ok(Box::new(EnergyVad::new(
                        super::super::VAD_FRAME_SAMPLES,
                        0.01,
                    )))
                },
                |pcm| {
                    assert_eq!(pcm, [0, 32].repeat(1001));
                    if cancelled {
                        stream.cancel();
                    }
                    Ok("dictated words".into())
                },
                &mut |event| {
                    match event {
                        LiveEvent::CaptureClosed => closed += 1,
                        LiveEvent::ReplaceTranscript(text) => {
                            assert_eq!(closed, 1);
                            commits.push(text);
                        }
                        LiveEvent::Hypothesis(_) => panic!("recorded mode must not emit previews"),
                        LiveEvent::Coverage(end) => covered = Some(end),
                        _ => {}
                    }
                    Ok(LiveControl::Continue)
                },
            );
            assert_eq!(closed, 1);
            if cancelled {
                assert_eq!(result, Err(VoiceError::Cancelled));
                assert!(commits.is_empty());
                assert_eq!(covered, None);
            } else {
                result.unwrap();
                assert_eq!(commits, ["dictated words"]);
                assert_eq!(covered, Some(1001));
            }
        }
    }

    #[test]
    fn silence_stop_preserves_transcription_when_a_capture_buffer_arrives_late() {
        use super::super::DictationState;
        use crate::voice::{CaptureFeedResult, StopReason};

        let stream = LiveTranscription::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap();
        let mut state = DictationState::new(false);
        state.session.begin_capture().unwrap();
        let mut audio = [0, 32].repeat(512);
        audio.extend(vec![0; (3 * 16000_usize).div_ceil(512) * 512 * 2]);
        let mut chunks = audio.chunks(1024);
        let mut capture_closed = false;
        let mut late_buffer = false;
        stream
            .run_recorded_with(
                || {
                    Ok(Box::new(EnergyVad::new(
                        super::super::VAD_FRAME_SAMPLES,
                        0.01,
                    )))
                },
                |pcm| {
                    assert_eq!(pcm, audio);
                    Ok("Complete recorded transcript".into())
                },
                &mut |event| {
                    let idle = matches!(event, LiveEvent::Idle);
                    if matches!(event, LiveEvent::CaptureClosed) {
                        capture_closed = true;
                    }
                    let control = state.apply(event, || stream.finish_if_empty())?;
                    if idle && state.session.stop_reason() == Some(StopReason::Silence) {
                        assert!(!capture_closed);
                        assert_eq!(stream.feed(&[0; 3200])?, CaptureFeedResult::Closed);
                        late_buffer = true;
                    } else if idle {
                        stream.feed(chunks.next().unwrap())?;
                    }
                    Ok(control)
                },
            )
            .unwrap();
        state.session.worker_exited(true).unwrap();
        assert!(late_buffer);
        assert!(capture_closed);
        assert_eq!(state.session.stop_reason(), Some(StopReason::Silence));
        assert!(!state.session.incomplete());
        assert_eq!(state.text(), "Complete recorded transcript");
        assert_eq!(stream.submitted_samples(), (audio.len() / 2) as u64);
    }
}
