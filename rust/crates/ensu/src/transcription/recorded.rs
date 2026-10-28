use std::time::Duration;

use transcribe_rs::vad::Vad;

use super::{LiveControl, LiveEvent, LiveTranscription, StreamNormalizer, Transcriber};
use crate::voice::{Result, VoiceError};

const MAX_RECORDED_SAMPLES: usize = (30 * 60 + 2) * 16_000;

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
            |pcm| {
                transcriber
                    .transcribe(16_000, pcm)
                    .map_err(|_| VoiceError::ProcessingFailed)
            },
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
                let voiced = vad
                    .is_speech(frame)
                    .map_err(|_| VoiceError::ProcessingFailed)?;
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
    fn recorded_text_arrives_once_after_close_with_partial_tail() {
        let stream = LiveTranscription::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap();
        stream.feed(&[0, 32].repeat(1001)).unwrap();
        stream.finish();
        let mut closed = false;
        let mut commits = Vec::new();
        let mut covered = 0;
        stream
            .run_recorded_with(
                || {
                    Ok(Box::new(EnergyVad::new(
                        super::super::VAD_FRAME_SAMPLES,
                        0.01,
                    )))
                },
                |pcm| {
                    assert_eq!(pcm.len(), 1001 * 2);
                    assert_eq!(pcm, [0, 32].repeat(1001));
                    Ok("dictated words".into())
                },
                &mut |event| {
                    match event {
                        LiveEvent::CaptureClosed => closed = true,
                        LiveEvent::ReplaceTranscript(text) => {
                            assert!(closed);
                            commits.push(text);
                        }
                        LiveEvent::Hypothesis(_) => panic!("recorded mode must not emit previews"),
                        LiveEvent::Coverage(end) => covered = end,
                        _ => {}
                    }
                    Ok(LiveControl::Continue)
                },
            )
            .unwrap();
        assert_eq!(commits, ["dictated words"]);
        assert_eq!(covered, 1001);
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
                        // A native read can finish after closure, before its stop callback.
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

    #[test]
    fn cancellation_during_batch_decode_does_not_publish_text() {
        let stream = LiveTranscription::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap();
        stream.feed(&[0, 32].repeat(512)).unwrap();
        stream.finish();
        let result = stream.run_recorded_with(
            || {
                Ok(Box::new(EnergyVad::new(
                    super::super::VAD_FRAME_SAMPLES,
                    0.01,
                )))
            },
            |_| {
                stream.cancel();
                Ok("late result".into())
            },
            &mut |event| {
                assert!(!matches!(
                    event,
                    LiveEvent::ReplaceTranscript(_) | LiveEvent::Coverage(_)
                ));
                Ok(LiveControl::Continue)
            },
        );
        assert_eq!(result, Err(VoiceError::Cancelled));
    }
}
