use std::path::Path;

use ente_assets::AssetStore;
use ente_ml::{assets, error::MlError, indexing, types};
use flutter_rust_bridge::spawn_blocking_with;

#[cfg(any(feature = "flutter", frb_expand))]
use crate::frb_generated::StreamSink;

#[derive(Clone, Debug)]
pub struct AnalyzeImageRequest {
    pub file_id: i64,
    pub image_path: String,
    pub run_faces: bool,
    pub run_clip: bool,
    pub run_pets: bool,
    pub assets_dir: String,
}

#[derive(Clone, Debug)]
pub enum RustMlError {
    InvalidImage { message: String },
    CorruptModel { message: String },
    Other { message: String },
}

#[derive(Clone, Debug)]
pub struct RustDimensions {
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Debug)]
pub struct RustDetection {
    pub score: f32,
    pub box_xyxy: Vec<f32>,
    pub all_keypoints: Vec<Vec<f32>>,
}

#[derive(Clone, Debug)]
pub struct RustAlignmentResult {
    pub affine_matrix: Vec<Vec<f32>>,
    pub center: Vec<f32>,
    pub size: f32,
    pub rotation: f32,
}

#[derive(Clone, Debug)]
pub struct RustFaceResult {
    pub detection: RustDetection,
    pub blur_value: f32,
    pub alignment: RustAlignmentResult,
    pub embedding: Vec<f32>,
    pub face_id: String,
}

#[derive(Clone, Debug)]
pub struct RustClipResult {
    pub embedding: Vec<f32>,
}

#[derive(Clone, Debug)]
pub struct RustPetFaceDetectionResult {
    pub score: f64,
    pub box_xyxy: Vec<f64>,
    // [left eye, right eye, nose], each as [x, y].
    pub keypoints: Vec<Vec<f64>>,
}

#[derive(Clone, Debug)]
pub struct RustPetAlignmentResult {
    pub center: Vec<f64>,
    pub angle: f64,
    pub crop_size: f64,
}

#[derive(Clone, Debug)]
pub struct RustPetFaceResult {
    pub detection: RustPetFaceDetectionResult,
    pub alignment: RustPetAlignmentResult,
    // 0 = dog, 1 = cat.
    pub species: u8,
    pub face_embedding: Vec<f64>,
    pub pet_face_id: String,
}

#[derive(Clone, Debug)]
pub struct RustPetBodyResult {
    pub box_xyxy: Vec<f64>,
    pub score: f64,
    // COCO class: 15 = cat, 16 = dog.
    pub coco_class: u8,
    pub pet_body_id: String,
    pub body_embedding: Vec<f64>,
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageResult {
    pub file_id: i64,
    pub decoded_image_size: RustDimensions,
    pub faces: Option<Vec<RustFaceResult>>,
    pub clip: Option<RustClipResult>,
    pub pet_faces: Option<Vec<RustPetFaceResult>>,
    pub pet_bodies: Option<Vec<RustPetBodyResult>>,
    pub used_coreml: bool,
    pub used_webgpu: bool,
}

#[derive(Clone, Debug)]
pub struct RunClipTextRequest {
    pub text: String,
    pub assets_dir: String,
}

#[derive(Clone, Debug)]
pub struct ModelDownloadProgress {
    pub model: String,
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct RunClipTextResult {
    pub embedding: Vec<f64>,
}

// This setting is process-wide. WebGPU is off by default and only used on
// Android 12+. Enable it before creating the first session.
pub fn set_ml_execution_config(enable_webgpu: bool) {
    indexing::set_ml_execution_config(enable_webgpu);
}

pub async fn init_ml_runtime(
    assets_dir: String,
    run_faces: bool,
    run_clip: bool,
    run_pets: bool,
) -> Result<(), RustMlError> {
    let store = AssetStore::new(&assets_dir);
    let paths = assets::ensure_indexing_models(
        &store,
        Path::new(&assets_dir),
        run_faces,
        run_clip,
        run_pets,
    )
    .await?;
    spawn_blocking_with(move || indexing::init_ml_runtime(paths), ())
        .await
        .map_err(task_error)
}

pub fn release_ml_runtime() {
    indexing::release_ml_runtime();
}

pub async fn analyze_image_rust(
    req: AnalyzeImageRequest,
) -> Result<AnalyzeImageResult, RustMlError> {
    let store = AssetStore::new(&req.assets_dir);
    let model_paths = assets::ensure_indexing_models(
        &store,
        Path::new(&req.assets_dir),
        req.run_faces,
        req.run_clip,
        req.run_pets,
    )
    .await?;
    let shared_req = indexing::AnalyzeImageRequest {
        file_id: req.file_id,
        source: indexing::ImageSource::Path(req.image_path),
        run_faces: req.run_faces,
        run_clip: req.run_clip,
        run_pets: req.run_pets,
        generate_face_crops: false,
        model_paths,
    };

    spawn_blocking_with(move || indexing::analyze_image(shared_req), ())
        .await
        .map_err(task_error)?
        .map(to_api_analyze_image_result)
        .map_err(RustMlError::from)
}

pub async fn run_clip_text_rust(req: RunClipTextRequest) -> Result<RunClipTextResult, RustMlError> {
    let store = AssetStore::new(&req.assets_dir);
    let paths = assets::ensure_clip_text(&store, Path::new(&req.assets_dir)).await?;
    let shared_req = indexing::RunClipTextRequest {
        text: req.text,
        model_path: paths.model.to_string_lossy().into_owned(),
        vocab_path: paths.vocab.to_string_lossy().into_owned(),
    };

    spawn_blocking_with(move || indexing::run_clip_text(shared_req), ())
        .await
        .map_err(task_error)?
        .map(|result| RunClipTextResult {
            embedding: result
                .embedding
                .into_iter()
                .map(|value| value as f64)
                .collect(),
        })
        .map_err(RustMlError::from)
}

pub fn tokenize_clip_text_rust(text: String, vocab_path: String) -> Result<Vec<i32>, String> {
    indexing::tokenize_clip_text(&text, &vocab_path).map_err(|e| e.to_string())
}

#[cfg(any(feature = "flutter", frb_expand))]
pub async fn preload_ml_models(
    assets_dir: String,
    run_faces: bool,
    run_clip: bool,
    run_pets: bool,
    include_clip_text: bool,
    progress: StreamSink<ModelDownloadProgress>,
) {
    let store = AssetStore::new(&assets_dir);
    let mut selected = assets::indexing_assets(run_faces, run_clip, run_pets);
    let mut labels = Vec::new();
    if run_faces {
        labels.extend(["face-detection", "face-embedding"]);
    }
    if run_clip {
        labels.push("clip-image");
    }
    if run_pets {
        labels.extend([
            "pet-face-detection",
            "pet-body-detection",
            "pet-face-embedding-dog",
            "pet-face-embedding-cat",
            "pet-body-embedding-dog",
            "pet-body-embedding-cat",
        ]);
    }
    if include_clip_text {
        selected.push(assets::clip_text_asset());
        labels.push("clip-text");
    }
    if let Err(error) =
        assets::ensure_mobile_models(&store, Path::new(&assets_dir), &selected, |update| {
            let _ = progress.add(ModelDownloadProgress {
                model: labels[update.asset_index].to_string(),
                downloaded_bytes: update.asset_progress.downloaded_bytes,
                total_bytes: update.asset_progress.total_bytes,
            });
        })
        .await
    {
        let _ = progress.add_error(error.to_string());
    }
}

pub fn is_clip_text_downloaded(assets_dir: String, include_vocab: bool) -> bool {
    assets::is_clip_text_available(
        &AssetStore::new(&assets_dir),
        Path::new(&assets_dir),
        include_vocab,
    )
}

fn task_error(error: impl std::fmt::Display) -> RustMlError {
    RustMlError::Other {
        message: error.to_string(),
    }
}

impl From<MlError> for RustMlError {
    fn from(value: MlError) -> Self {
        match value {
            MlError::Decode(message) | MlError::Image(message) => Self::InvalidImage { message },
            MlError::CorruptModel(message) => Self::CorruptModel { message },
            MlError::InvalidRequest(message)
            | MlError::Preprocess(message)
            | MlError::Ort(message)
            | MlError::Postprocess(message)
            | MlError::Runtime(message) => Self::Other { message },
        }
    }
}

fn to_api_analyze_image_result(result: indexing::AnalyzeImageResult) -> AnalyzeImageResult {
    AnalyzeImageResult {
        file_id: result.file_id,
        decoded_image_size: RustDimensions {
            width: result.decoded_image_size.width as i32,
            height: result.decoded_image_size.height as i32,
        },
        faces: result
            .faces
            .map(|faces| faces.into_iter().map(to_api_face_result).collect()),
        clip: result.clip.map(|clip| RustClipResult {
            embedding: clip.embedding,
        }),
        pet_faces: result
            .pet_faces
            .map(|faces| faces.into_iter().map(to_api_pet_face_result).collect()),
        pet_bodies: result
            .pet_bodies
            .map(|bodies| bodies.into_iter().map(to_api_pet_body_result).collect()),
        used_coreml: result.used_coreml,
        used_webgpu: result.used_webgpu,
    }
}

fn to_api_face_result(result: types::FaceResult) -> RustFaceResult {
    RustFaceResult {
        detection: RustDetection {
            score: result.detection.score,
            box_xyxy: result.detection.box_xyxy.into_iter().collect(),
            all_keypoints: result
                .detection
                .keypoints
                .into_iter()
                .map(|point| point.into_iter().collect())
                .collect(),
        },
        blur_value: result.blur_value,
        alignment: RustAlignmentResult {
            affine_matrix: result
                .alignment
                .affine_matrix
                .into_iter()
                .map(|row| row.into_iter().collect())
                .collect(),
            center: result.alignment.center.into_iter().collect(),
            size: result.alignment.size,
            rotation: result.alignment.rotation,
        },
        embedding: result.embedding,
        face_id: result.face_id,
    }
}

fn to_api_pet_face_result(result: types::PetFaceResult) -> RustPetFaceResult {
    RustPetFaceResult {
        detection: RustPetFaceDetectionResult {
            score: result.detection.score as f64,
            box_xyxy: result
                .detection
                .box_xyxy
                .into_iter()
                .map(|v| v as f64)
                .collect(),
            keypoints: result
                .detection
                .keypoints
                .into_iter()
                .map(|point| point.into_iter().map(|v| v as f64).collect())
                .collect(),
        },
        alignment: RustPetAlignmentResult {
            center: result
                .alignment
                .center
                .into_iter()
                .map(|v| v as f64)
                .collect(),
            angle: result.alignment.angle as f64,
            crop_size: result.alignment.crop_size as f64,
        },
        species: result.species,
        face_embedding: result
            .face_embedding
            .into_iter()
            .map(|v| v as f64)
            .collect(),
        pet_face_id: result.pet_face_id,
    }
}

fn to_api_pet_body_result(result: types::PetBodyResult) -> RustPetBodyResult {
    RustPetBodyResult {
        box_xyxy: result
            .detection
            .box_xyxy
            .into_iter()
            .map(|v| v as f64)
            .collect(),
        score: result.detection.score as f64,
        coco_class: result.detection.coco_class,
        pet_body_id: result.pet_body_id,
        body_embedding: result
            .body_embedding
            .into_iter()
            .map(|v| v as f64)
            .collect(),
    }
}
