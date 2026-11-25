CREATE TABLE parents (
    id TEXT PRIMARY KEY NOT NULL,
    created_at INTEGER NOT NULL
) STRICT;

CREATE TABLE devices (
    id TEXT PRIMARY KEY NOT NULL,
    parent_id TEXT UNIQUE REFERENCES parents(id) ON DELETE RESTRICT,
    pairing_id TEXT UNIQUE,
    paired_at INTEGER,
    push_token TEXT,
    CHECK (
        (parent_id IS NULL AND pairing_id IS NULL AND paired_at IS NULL)
        OR (parent_id IS NOT NULL AND pairing_id IS NOT NULL AND paired_at IS NOT NULL)
    )
) STRICT;

CREATE TABLE pair_codes (
    code TEXT PRIMARY KEY NOT NULL
        CHECK (length(code) = 6 AND code NOT GLOB '*[^0-9]*'),
    device_id TEXT NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,
    expires_at INTEGER NOT NULL
) STRICT;

CREATE INDEX pair_codes_expiry ON pair_codes(expires_at);

CREATE TABLE commands (
    id TEXT PRIMARY KEY NOT NULL,
    parent_id TEXT NOT NULL REFERENCES parents(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    pairing_id TEXT NOT NULL,
    command TEXT NOT NULL CHECK (command IN (
        'lock', 'vibrate', 'sound', 'flashlight', 'message', 'alarm', 'silent',
        'ringer_normal', 'dnd_on', 'dnd_off', 'battery_status'
    )),
    message TEXT CHECK (message IS NULL OR length(message) BETWEEN 1 AND 160),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'completed', 'declined', 'failed', 'expired')),
    result TEXT CHECK (result IS NULL OR length(result) <= 300),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
    CHECK ((command = 'message' AND message IS NOT NULL) OR
           (command <> 'message' AND message IS NULL))
) STRICT;

CREATE INDEX commands_parent_history ON commands(parent_id, created_at DESC);
CREATE INDEX commands_device_pending ON commands(device_id, pairing_id, expires_at)
    WHERE status = 'pending';

CREATE TABLE rate_limits (
    key TEXT PRIMARY KEY NOT NULL,
    count INTEGER NOT NULL CHECK (count > 0),
    expires_at INTEGER NOT NULL
) STRICT;

CREATE INDEX rate_limits_expiry ON rate_limits(expires_at);
