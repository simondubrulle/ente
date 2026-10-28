mod audio;
mod capture;
mod composer;
mod rolling;
mod session;

pub use audio::*;
pub use capture::*;
pub use composer::*;
pub use rolling::*;
pub use session::*;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum VoiceError {
    #[error("Audio continuity or format is invalid")]
    InvalidAudio,
    #[error("Audio backlog limit reached")]
    BacklogFull,
    #[error("Voice recording was cancelled")]
    Cancelled,
    #[error("Speech alignment could not be preserved")]
    UnstableTranscript,
    #[error("Speech processing failed")]
    ProcessingFailed,
    #[error("Voice event belongs to an inactive recording")]
    StaleEvent,
    #[error("Voice operation is not valid in the current state")]
    InvalidState,
    #[error("Text range is not on a character boundary")]
    InvalidTextRange,
    #[error("Text or destination changed")]
    RevisionConflict,
    #[error("Some speech could not be finalized")]
    IncompleteAudio,
    #[error("Keyboard input is still composing")]
    PendingEdit,
}

pub type Result<T> = std::result::Result<T, VoiceError>;
