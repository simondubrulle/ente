mod audio;
mod graph_cache;
mod live;
mod normalize;
mod recorded;
mod session;
mod transcriber;
mod vad;

pub use live::{LiveControl, LiveEvent, LiveTranscription};
pub(crate) use normalize::{StreamNormalizer, VAD_FRAME_SAMPLES};
pub use session::DictationState;
pub use transcriber::Transcriber;
pub(crate) use vad::SileroV4Vad;

#[derive(Debug, thiserror::Error)]
pub enum TranscriptionError {
    #[error("Transcription model is not downloaded")]
    NotDownloaded,
    #[error("Voice activity model is not downloaded")]
    VadNotDownloaded,
    #[error("{0}")]
    InvalidAudio(String),
    #[error("{0}")]
    Transcribe(String),
    #[error("not enough storage space")]
    StorageFull,
    #[error(transparent)]
    Io(std::io::Error),
}

impl From<std::io::Error> for TranscriptionError {
    fn from(err: std::io::Error) -> Self {
        if err.kind() == std::io::ErrorKind::StorageFull {
            Self::StorageFull
        } else {
            Self::Io(err)
        }
    }
}

impl From<transcribe_rs::TranscribeError> for TranscriptionError {
    fn from(value: transcribe_rs::TranscribeError) -> Self {
        Self::Transcribe(value.to_string())
    }
}

impl<R> From<ort::Error<R>> for TranscriptionError {
    fn from(value: ort::Error<R>) -> Self {
        Self::Transcribe(value.to_string())
    }
}

impl From<rubato::ResamplerConstructionError> for TranscriptionError {
    fn from(value: rubato::ResamplerConstructionError) -> Self {
        Self::InvalidAudio(value.to_string())
    }
}

pub type Result<T> = std::result::Result<T, TranscriptionError>;
