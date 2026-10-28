use std::ops::Range;

use super::{Result, VoiceError};

pub fn utf16_range(text: &str, start: u32, end: u32) -> Result<Range<usize>> {
    if start > end {
        return Err(VoiceError::InvalidTextRange);
    }
    let mut units = 0_u32;
    let mut from = None;
    for (byte, character) in text
        .char_indices()
        .chain(std::iter::once((text.len(), '\0')))
    {
        if units == start {
            from = Some(byte);
        }
        if units == end {
            return Ok(from.ok_or(VoiceError::InvalidTextRange)?..byte);
        }
        units = units
            .checked_add(character.len_utf16() as u32)
            .ok_or(VoiceError::InvalidTextRange)?;
    }
    Err(VoiceError::InvalidTextRange)
}

pub fn boundary_separator(left: &str, right: &str) -> &'static str {
    fn unspaced(c: char) -> bool {
        matches!(c as u32, 0x3040..=0x30ff | 0x3400..=0x9fff | 0x20000..=0x3134f)
    }
    let left_edge = left
        .chars()
        .rev()
        .find(|c| {
            !regex::regex!(r"\A[\p{M}\p{Join_Control}]\z").is_match(c.encode_utf8(&mut [0; 4]))
        })
        .or_else(|| left.chars().next());
    let right_edge = right.chars().next();
    match (left_edge, right_edge) {
        (Some(a), Some(b))
            if (a.is_alphanumeric()
                || matches!(
                    a,
                    '.' | '!' | '?' | ':' | ';' | ',' | '।' | '॥' | '؟' | '؛' | '،'
                ))
                && b.is_alphanumeric()
                && !unspaced(a)
                && !unspaced(b) =>
        {
            " "
        }
        _ => "",
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ComposerAnchor {
    pub destination: String,
    pub revision: u64,
    pub start_utf16: u32,
    pub end_utf16: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceInsertion {
    pub anchor: ComposerAnchor,
    pub text: String,
}

pub fn preview_insertion(
    text: &str,
    anchor: &ComposerAnchor,
    voice_text: &str,
) -> Result<(String, u32)> {
    let range = utf16_range(text, anchor.start_utf16, anchor.end_utf16)?;
    if voice_text.is_empty() {
        return Ok((text.to_owned(), anchor.end_utf16));
    }
    let before = &text[..range.start];
    let after = &text[range.end..];
    let prefix = boundary_separator(before, voice_text);
    let suffix = boundary_separator(voice_text, after);
    let caret = before.encode_utf16().count()
        + prefix.encode_utf16().count()
        + voice_text.encode_utf16().count()
        + suffix.encode_utf16().count();
    Ok((
        format!("{before}{prefix}{voice_text}{suffix}{after}"),
        caret as u32,
    ))
}

#[derive(Debug, Default)]
pub struct ComposerTransfer {
    receipt: Option<(VoiceInsertion, u32)>,
}

impl ComposerTransfer {
    pub fn apply(
        &mut self,
        insertion: &VoiceInsertion,
        destination: &str,
        revision: &mut u64,
        text: &mut String,
        foreground: bool,
        composing: bool,
    ) -> Result<u32> {
        if let Some((applied, receipt)) = &self.receipt {
            return if applied == insertion {
                Ok(*receipt)
            } else {
                Err(VoiceError::RevisionConflict)
            };
        }
        if !foreground || insertion.anchor.destination != destination {
            return Err(VoiceError::RevisionConflict);
        }
        if composing {
            return Err(VoiceError::PendingEdit);
        }
        if insertion.text.trim().is_empty() {
            return Err(VoiceError::InvalidState);
        }
        let mut anchor = insertion.anchor.clone();
        if anchor.revision != *revision {
            anchor.start_utf16 = text.encode_utf16().count() as u32;
            anchor.end_utf16 = anchor.start_utf16;
        }
        let (rendered, caret) = preview_insertion(text, &anchor, &insertion.text)?;
        *text = rendered;
        *revision += 1;
        self.receipt = Some((insertion.clone(), caret));
        Ok(caret)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn insertion(start: u32, end: u32, text: &str) -> VoiceInsertion {
        VoiceInsertion {
            text: text.into(),
            anchor: ComposerAnchor {
                destination: "chat".into(),
                revision: 7,
                start_utf16: start,
                end_utf16: end,
            },
        }
    }

    #[test]
    fn selected_text_is_replaced_once_even_after_lost_acknowledgement() {
        let mut owner = ComposerTransfer::default();
        let mut text = "  meet Friday\n".to_owned();
        let mut revision = 7;
        let insert = insertion(7, 13, "Saturday");
        let receipt = owner
            .apply(&insert, "chat", &mut revision, &mut text, true, false)
            .unwrap();
        assert_eq!(text, "  meet Saturday\n");
        assert_eq!(
            owner
                .apply(
                    &insert,
                    "different-chat",
                    &mut revision,
                    &mut text,
                    false,
                    false
                )
                .unwrap(),
            receipt
        );
        assert_eq!(revision, 8);
        assert_eq!(text, "  meet Saturday\n");
    }

    #[test]
    fn changed_draft_appends_once_but_a_different_chat_is_rejected() {
        let mut owner = ComposerTransfer::default();
        let mut text = "My edited draft".to_owned();
        let mut revision = 8;
        let insert = insertion(0, 0, "hello");
        for (destination, foreground, composing) in [
            ("another-chat", true, false),
            ("chat", false, false),
            ("chat", true, true),
        ] {
            assert!(
                owner
                    .apply(
                        &insert,
                        destination,
                        &mut revision,
                        &mut text,
                        foreground,
                        composing
                    )
                    .is_err()
            );
        }
        assert_eq!(text, "My edited draft");
        owner
            .apply(&insert, "chat", &mut revision, &mut text, true, false)
            .unwrap();
        assert_eq!(text, "My edited draft hello");
        owner
            .apply(&insert, "chat", &mut revision, &mut text, true, false)
            .unwrap();
        assert_eq!(text, "My edited draft hello");
        assert_eq!(revision, 9);
    }

    #[test]
    fn utf16_ranges_preserve_text_and_reject_split_surrogates() {
        for text in ["👩🏽‍💻", "e\u{301}", "कि", "क्ष"] {
            let end = text.encode_utf16().count() as u32;
            assert_eq!(utf16_range(text, 0, end).unwrap(), 0..text.len());
            for (byte, character) in text.char_indices() {
                let start = text[..byte].encode_utf16().count() as u32;
                assert_eq!(
                    utf16_range(text, start, start + character.len_utf16() as u32).unwrap(),
                    byte..byte + character.len_utf8()
                );
                if character.len_utf16() == 2 {
                    assert_eq!(
                        utf16_range(text, start, start + 1),
                        Err(VoiceError::InvalidTextRange)
                    );
                    assert_eq!(
                        utf16_range(text, start + 1, end),
                        Err(VoiceError::InvalidTextRange)
                    );
                }
            }
        }
        for (start, end) in [(2, 1), (0, 9), (9, 9)] {
            assert_eq!(
                utf16_range("hello", start, end),
                Err(VoiceError::InvalidTextRange)
            );
        }
        assert_eq!(utf16_range("你好 مرحبا", 0, 2).unwrap(), 0..6);
    }

    #[test]
    fn insertion_preserves_whitespace_and_script_boundaries() {
        assert_eq!(boundary_separator("hello", "world"), " ");
        assert_eq!(boundary_separator("你好", "世界"), "");
        assert_eq!(boundary_separator("hello\n", "world"), "");
        assert_eq!(boundary_separator("مرحبا", "بك"), " ");
        assert_eq!(boundary_separator("कि", "Saturday"), " ");
        assert_eq!(boundary_separator("क्‍", "Saturday"), " ");
        assert_eq!(boundary_separator("cafe\u{301}", "Saturday"), " ");
        assert_eq!(boundary_separator("你\u{301}", "好"), "");
        assert_eq!(boundary_separator("👩🏽‍💻", "Saturday"), "");
        assert_eq!(boundary_separator("Done.", "Next"), " ");
        assert_eq!(boundary_separator("है।", "बैठक"), " ");
        assert_eq!(boundary_separator("نعم؟", "موعد"), " ");
        assert_eq!(boundary_separator("안녕", "친구"), " ");
    }
}
