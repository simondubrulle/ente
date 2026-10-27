use ente_photobook::Error as E;
use wasm_bindgen::prelude::*;

pub struct Error(E);

impl From<E> for Error {
    fn from(error: E) -> Self {
        Self(error)
    }
}

impl From<Error> for JsValue {
    fn from(Error(error): Error) -> Self {
        let name = match error {
            E::InvalidProfile(_) | E::NotCmykProfile => Some("invalid_profile"),
            E::InvalidDimensions { .. } => Some("invalid_dimensions"),
            E::InvalidQuality(_) => Some("invalid_quality"),
            E::Convert(_) | E::Encode(_) => None,
        };
        ente_wasm_lib::js_error(&error, name)
    }
}

#[wasm_bindgen]
pub struct CmykJpegEncoder(ente_photobook::CmykJpegEncoder);

#[wasm_bindgen]
impl CmykJpegEncoder {
    #[wasm_bindgen(constructor)]
    pub fn new(output_profile: &[u8]) -> Result<Self, Error> {
        Ok(Self(ente_photobook::CmykJpegEncoder::new(output_profile)?))
    }

    pub fn encode(
        &self,
        srgb_rgba: Vec<u8>,
        width: u16,
        height: u16,
        quality: u8,
    ) -> Result<Vec<u8>, Error> {
        Ok(self.0.encode(srgb_rgba, width, height, quality)?)
    }
}
