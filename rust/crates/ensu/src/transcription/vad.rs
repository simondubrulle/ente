use ort::{
    inputs,
    session::{Session, builder::GraphOptimizationLevel},
    value::TensorRef,
};
use std::path::Path;
use transcribe_rs::{TranscribeError, vad::Vad};

pub(super) const SILERO_V4_FRAME_SAMPLES: usize = 512;

pub(crate) struct SileroV4Vad {
    session: Session,
    hidden: [f32; 128],
    cell: [f32; 128],
}

fn inference(error: impl std::fmt::Display) -> TranscribeError {
    TranscribeError::Inference(format!("Silero v4: {error}"))
}

impl SileroV4Vad {
    pub fn new(path: impl AsRef<Path>) -> Result<Self, TranscribeError> {
        let session = Session::builder()
            .map_err(inference)?
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .map_err(inference)?
            .with_intra_threads(1)
            .map_err(inference)?
            .with_inter_threads(1)
            .map_err(inference)?
            .commit_from_file(path)
            .map_err(inference)?;
        Ok(Self {
            session,
            hidden: [0.0; 128],
            cell: [0.0; 128],
        })
    }

    fn speech_probability(&mut self, frame: &[f32]) -> Result<f32, TranscribeError> {
        validate_frame(frame)?;
        let sample_rate = [16000_i64];
        let outputs = self.session.run(inputs![
            "input" => TensorRef::from_array_view(([1, SILERO_V4_FRAME_SAMPLES], frame)).map_err(inference)?,
            "sr" => TensorRef::from_array_view(([1], sample_rate.as_slice())).map_err(inference)?,
            "h" => TensorRef::from_array_view(([2,1,64], self.hidden.as_slice())).map_err(inference)?,
            "c" => TensorRef::from_array_view(([2,1,64], self.cell.as_slice())).map_err(inference)?,
        ]).map_err(inference)?;
        let (shape, probability) = outputs
            .get("output")
            .ok_or_else(|| inference("missing probability"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        if shape.as_ref() != [1, 1]
            || probability.len() != 1
            || !probability[0].is_finite()
            || !(0.0..=1.0).contains(&probability[0])
        {
            return Err(inference("invalid probability"));
        }
        let probability = probability[0];
        let (h_shape, hidden) = outputs
            .get("hn")
            .ok_or_else(|| inference("missing hidden state"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        let (c_shape, cell) = outputs
            .get("cn")
            .ok_or_else(|| inference("missing cell state"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        if h_shape.as_ref() != [2, 1, 64]
            || c_shape.as_ref() != [2, 1, 64]
            || hidden.len() != 128
            || cell.len() != 128
            || hidden.iter().chain(cell).any(|x| !x.is_finite())
        {
            return Err(inference("invalid recurrent state"));
        }
        self.hidden.copy_from_slice(hidden);
        self.cell.copy_from_slice(cell);
        Ok(probability)
    }
}

fn validate_frame(frame: &[f32]) -> Result<(), TranscribeError> {
    if frame.len() != SILERO_V4_FRAME_SAMPLES || frame.iter().any(|s| !s.is_finite()) {
        return Err(TranscribeError::Audio(
            "Silero v4 requires 512 finite samples at 16 kHz".into(),
        ));
    }
    Ok(())
}

impl Vad for SileroV4Vad {
    fn frame_size(&self) -> usize {
        SILERO_V4_FRAME_SAMPLES
    }
    fn is_speech(&mut self, frame: &[f32]) -> Result<bool, TranscribeError> {
        Ok(self.speech_probability(frame)? > 0.5)
    }
    fn reset(&mut self) {
        self.hidden.fill(0.0);
        self.cell.fill(0.0);
    }
}
