use crate::config::{EMBEDDING_CONTEXT_SIZE, ModelRuntimeSurface};

const MIB: u64 = 1024 * 1024;
const MEMORY_RESERVE_BYTES: u64 = 256 * MIB;
const EMBEDDING_QUERY_OVERHEAD: u64 = 64;
const CALIBRATED_LFM_ID: &str = "lfm-vl-1.6b";
const CALIBRATED_LFM_BYTES: u64 = 695_752_480;
const CALIBRATED_LFM_MAX_CONTEXT: u32 = 12032;

pub fn has_required_work_reserve(available_bytes: Option<u64>) -> bool {
    available_bytes.is_none_or(|available| available >= MEMORY_RESERVE_BYTES)
}

#[derive(Debug, Clone, Copy)]
pub enum MemoryOperation {
    Embedding,
    Voice,
    Title,
}

pub struct ChatModelMemory {
    pub model_id: String,
    pub model_bytes: u64,
    pub context_size: u32,
}

pub struct MemoryBudget {
    pub required_bytes: u64,
    pub system_reserve_cap_bytes: Option<u64>,
}

pub fn memory_budget(
    surface: ModelRuntimeSurface,
    operation: MemoryOperation,
    loaded_chat: Option<&ChatModelMemory>,
    query_bytes: Option<u64>,
) -> MemoryBudget {
    let token_bound = query_bytes
        .map(|bytes| bytes.min(u64::from(EMBEDDING_CONTEXT_SIZE)) + EMBEDDING_QUERY_OVERHEAD);
    let short_query = token_bound.is_some_and(|tokens| tokens <= 512);
    if matches!(surface, ModelRuntimeSurface::Android)
        && matches!(operation, MemoryOperation::Embedding)
        && loaded_chat.is_some_and(|chat| {
            chat.model_id == CALIBRATED_LFM_ID
                && chat.model_bytes == CALIBRATED_LFM_BYTES
                && (1..=CALIBRATED_LFM_MAX_CONTEXT).contains(&chat.context_size)
        })
        && short_query
    {
        let additional_mib = if token_bound.is_some_and(|tokens| tokens <= 256) {
            768
        } else {
            1024
        };
        return MemoryBudget {
            required_bytes: additional_mib * MIB + MEMORY_RESERVE_BYTES,
            system_reserve_cap_bytes: Some(512 * MIB),
        };
    }
    let additional_bytes = match operation {
        MemoryOperation::Embedding if short_query => 1024 * MIB,
        MemoryOperation::Embedding => 2560 * MIB,
        MemoryOperation::Voice => 2048 * MIB,
        MemoryOperation::Title => 512 * MIB,
    };
    MemoryBudget {
        required_bytes: additional_bytes + MEMORY_RESERVE_BYTES,
        system_reserve_cap_bytes: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn required_work_preserves_minimum_reserve() {
        assert!(!has_required_work_reserve(Some(MEMORY_RESERVE_BYTES - 1)));
        assert!(has_required_work_reserve(Some(MEMORY_RESERVE_BYTES)));
        assert!(has_required_work_reserve(None));
    }

    #[test]
    fn generic_budgets_cover_query_boundaries_and_required_reserve() {
        for (operation, query_bytes, required_mib) in [
            (MemoryOperation::Embedding, None, 2816),
            (MemoryOperation::Embedding, Some(0), 1280),
            (MemoryOperation::Embedding, Some(448), 1280),
            (MemoryOperation::Embedding, Some(449), 2816),
            (MemoryOperation::Embedding, Some(u64::MAX), 2816),
            (MemoryOperation::Voice, None, 2304),
            (MemoryOperation::Title, None, 768),
        ] {
            let budget = memory_budget(ModelRuntimeSurface::Android, operation, None, query_bytes);
            assert_eq!(budget.required_bytes, required_mib * MIB);
            assert_eq!(budget.system_reserve_cap_bytes, None);
        }
    }

    #[test]
    fn android_calibration_is_limited_to_short_queries() {
        let chat = ChatModelMemory {
            model_id: "lfm-vl-1.6b".into(),
            model_bytes: 695_752_480,
            context_size: 12032,
        };
        for (query_bytes, required_mib, reserve_cap) in [
            (Some(0), 1024, Some(512 * MIB)),
            (Some(192), 1024, Some(512 * MIB)),
            (Some(193), 1280, Some(512 * MIB)),
            (Some(448), 1280, Some(512 * MIB)),
            (Some(449), 2816, None),
            (Some(u64::MAX), 2816, None),
            (None, 2816, None),
        ] {
            let budget = memory_budget(
                ModelRuntimeSurface::Android,
                MemoryOperation::Embedding,
                Some(&chat),
                query_bytes,
            );
            assert_eq!(budget.required_bytes, required_mib * MIB);
            assert_eq!(budget.system_reserve_cap_bytes, reserve_cap);
        }
        for (operation, required_mib) in [
            (MemoryOperation::Voice, 2304),
            (MemoryOperation::Title, 768),
        ] {
            let budget = memory_budget(
                ModelRuntimeSurface::Android,
                operation,
                Some(&chat),
                Some(0),
            );
            assert_eq!(budget.required_bytes, required_mib * MIB);
            assert_eq!(budget.system_reserve_cap_bytes, None);
        }
    }

    #[test]
    fn unmeasured_platforms_models_and_contexts_keep_generic_budgets() {
        for (surface, model_id, model_bytes, context_size) in [
            (ModelRuntimeSurface::Ios, "lfm-vl-1.6b", 695_752_480, 4096),
            (
                ModelRuntimeSurface::Desktop,
                "lfm-vl-1.6b",
                695_752_480,
                4096,
            ),
            (ModelRuntimeSurface::Android, "gemma", 695_752_480, 4096),
            (
                ModelRuntimeSurface::Android,
                "lfm-vl-1.6b",
                695_752_481,
                4096,
            ),
            (ModelRuntimeSurface::Android, "lfm-vl-1.6b", 695_752_480, 0),
            (
                ModelRuntimeSurface::Android,
                "lfm-vl-1.6b",
                695_752_480,
                12033,
            ),
        ] {
            let chat = ChatModelMemory {
                model_id: model_id.into(),
                model_bytes,
                context_size,
            };
            let budget = memory_budget(surface, MemoryOperation::Embedding, Some(&chat), Some(128));
            assert_eq!(budget.required_bytes, 1280 * MIB);
            assert_eq!(budget.system_reserve_cap_bytes, None);
        }
    }
}
