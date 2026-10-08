ALTER TABLE push_tokens
    ADD COLUMN platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
    ADD COLUMN notification_public_key BYTEA CHECK (octet_length(notification_public_key) = 32);
