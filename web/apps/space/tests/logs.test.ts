import log, { logToDisk, setLogSanitizer } from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { sanitizeSpaceLog } from "../src/utils/logs";

const requestID = "ed2d1157-f958-489c-aa59-25b49f560b8a";

beforeEach(() => {
    const items = new Map<string, string>();
    vi.stubGlobal("localStorage", {
        getItem: (key: string) => items.get(key) ?? null,
        setItem: (key: string, value: string) => items.set(key, value),
        removeItem: (key: string) => items.delete(key),
    });
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    setLogSanitizer(sanitizeSpaceLog);
});

afterEach(() => {
    setLogSanitizer((message) => message);
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
});

test("saves upload diagnostics without URLs, credentials, or error payloads", () => {
    const error = new Error(
        "HTTP 429 SPACE_UPLOAD_LIMIT_REACHED at https://api.test/spaces/private-space?token=secret-token alice@example.test caption=Family birthday",
    );
    error.stack = `Error: ${error.message}\n at /Users/Alice/holiday.jpg:4:8`;
    log.error(
        `Space post upload failed ${JSON.stringify({ requestId: requestID, stage: "upload-video", itemIndex: 2, itemCount: 3, bytes: 4096 })}`,
        error,
    );
    const expected = `[error] Space post upload failed request=${requestID} stage=upload-video itemIndex=2 itemCount=3 bytes=4096 status=429 code=SPACE_UPLOAD_LIMIT_REACHED`;
    const entries = JSON.parse(localStorage.getItem("logs")!) as {
        logs: { logLine: string }[];
    };
    expect(entries.logs.map((entry) => entry.logLine)).toEqual([expected]);
    expect(savedLogs(sanitizeSpaceLog).split("] ").slice(1).join("] ")).toBe(
        expected,
    );
});

test.each([
    "[info] Profile Alice Example alice@example.test +1-202-555-0100 uid 12345",
    "[warn] [rust] ente_space::client::profiles: Space profile private-space fell back to public fields: private payload",
    "[info] Starting ente-space-web uid 12345",
    "[error] Unhandled error: private message with a caption and auth token\n at https://space.test/alice?token=secret",
    "[info] [wasm] ffmpeg command failed: /Users/Alice/private-video.mp4",
])("does not retain arbitrary personal data in %s", (message) => {
    logToDisk(message);
    expect(savedLogs()).not.toMatch(
        /Alice|alice|example\.test|202-555|12345|private|secret|https:/,
    );
});

test("filters legacy entries and unexpected records again on download", () => {
    localStorage.setItem(
        "logs",
        JSON.stringify({
            logs: [
                {
                    timestamp: 0,
                    logLine:
                        "[error] Failed to publish space post: Error: HTTP 503 at https://api.test/spaces/private-space/posts?token=secret",
                },
                "alice@example.test",
                { caption: "Family birthday" },
            ],
        }),
    );
    expect(savedLogs(sanitizeSpaceLog)).toBe(
        "[1970-01-01T00:00:00.000Z] [error] Failed to publish space post status=503\n[info] Application event\n[info] Application event",
    );
});

test.each([
    [
        `[error] Space post failed request=${requestID} attempt=2 elapsedMs=450: TypeError: Failed to fetch`,
        "attempt=2 elapsedMs=450 reason=Failed to fetch",
    ],
    [
        `[error] Space post preparation failed request=${requestID} item=2/3 type=image/jpeg bytes=500: Error: Could not decode image at /Users/Alice/photo.jpg`,
        "item=2/3 bytes=500 type=image/jpeg reason=Could not decode image",
    ],
    [
        "[warn] [rust] ente_core::http: retrying in 5s: HTTP 503 at https://bucket.test/object?signature=secret",
        "delaySeconds=5 status=503",
    ],
    [
        "[error] Space post failed: post_limit_reached: space post limit reached",
        "code=post_limit_reached reason=space post limit reached",
    ],
    [
        "[info] [wasm] ffmpeg command failed with exit code 1: -i /Users/Alice/private.mp4",
        "exitCode=1",
    ],
])(
    "keeps useful diagnostics and remains safe on repeated filtering",
    (message, expected) => {
        const sanitized = sanitizeSpaceLog(message);
        expect(sanitized).toContain(expected);
        expect(sanitizeSpaceLog(sanitized)).toBe(sanitized);
        expect(sanitized).not.toMatch(/Alice|photo\.jpg|https:|secret/);
    },
);

test("does not extract upload metadata from exception text", () => {
    expect(
        sanitizeSpaceLog(
            `[error] Space post failed: TypeError: request=${requestID} bytes=2025550100`,
        ),
    ).toBe("[error] Space post failed reason=TypeError");
});

test("leaves shared logging unchanged when no Space filter is configured", () => {
    setLogSanitizer((message) => message);
    logToDisk("[info] A Photos diagnostic");
    expect(savedLogs()).toContain("[info] A Photos diagnostic");
});
