const events = [
    "Space post upload failed",
    "Space post preparation failed",
    "Space post failed",
    "Space post published",
    "Failed to publish space post",
    "Failed to refresh a published post",
    "Failed to prepare post preview",
    "Failed to prepare edited post photos",
    "WebCodecs export failed, using FFmpeg",
    "[wasm] ffmpeg command failed",
    "[wasm] ffprobe command failed",
    "[rust] ente_core::http: retrying",
    "Failed to load space feed",
    "Failed to load space profile",
    "Failed to decrypt Space browser session",
    "Space login email verification failed",
    "Space signup verification failed",
    "Space 2FA verification failed",
    "Space passkey verification failed",
    "Unhandled error",
    "Unhandled promise rejection",
    "Application error",
    "Application warning",
    "Application event",
];

const errorCodes = [
    "SPACE_UPLOAD_LIMIT_REACHED",
    "post_limit_reached",
    "UNAUTHORIZED",
    "PERMISSION_DENIED",
    "BAD_REQUEST",
    "NOT_FOUND",
    "CONFLICT",
    "RATE_LIMIT_EXCEEDED",
];

const errorReasons = [
    "error sending request",
    "Failed to fetch",
    "Load failed",
    "NetworkError",
    "TimeoutError",
    "AbortError",
    "QuotaExceededError",
    "NotSupportedError",
    "EncodingError",
    "SecurityError",
    "SpaceImageTypeError",
    "SpaceImageSizeError",
    "Only photos can be uploaded.",
    "This photo is too large. Try a smaller one.",
    "Could not decode image",
    "Could not encode image",
    "Could not create image canvas",
    "Invalid image dimensions",
    "This browser can't preview this video.",
    "The video took too long to load.",
    "This video has no readable duration.",
    "Couldn't prepare the video cover.",
    "Choose a video segment of up to 10 seconds.",
    "This video is too large. Try a shorter trim.",
    "Couldn't export a video within 10 seconds.",
    "Couldn't read video packets",
    "Couldn't prepare the video frames",
    "Video export is missing frames",
    "space post limit reached",
    "missing secret key material",
    "TypeError",
    "RangeError",
    "SyntaxError",
];

const uploadFields: [string, RegExp][] = [
    [
        "request",
        /(?:request=|"requestId":")([a-f\d]{8}-[a-f\d]{4}-4[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12})\b/i,
    ],
    [
        "stage",
        /(?:stage=|"stage":")(prepare|upload-preview|upload-video|create-post)\b/,
    ],
    ["attempt", /\battempt=(\d{1,6})\b/],
    ["elapsedMs", /\belapsedMs=(\d{1,12})\b/],
    ["item", /\bitem=(\d{1,2}\/\d{1,2})\b/],
    ["itemIndex", /(?:itemIndex=|"itemIndex":)(\d{1,2})\b/],
    ["itemCount", /(?:itemCount=|"itemCount":)(\d{1,2})\b/],
    ["bytes", /(?:bytes=|"bytes":)(\d{1,12})\b/],
    [
        "type",
        /\btype=((?:image\/(?:jpeg|jpg|png|webp|heic|heif)|video\/(?:mp4|quicktime|webm)))(?=\s|$)/,
    ],
];

export const sanitizeSpaceLog = (message: string) => {
    const level = /^\[(error|warn|info)\] /.exec(message)?.[1] ?? "info";
    const body = message.replace(/^\[(error|warn|info)\] /, "");
    const event =
        events.find((event) => body.startsWith(event)) ??
        (level == "error"
            ? "Application error"
            : level == "warn"
              ? "Application warning"
              : "Application event");
    const details = [`[${level}] ${event}`];
    if (event.startsWith("Space post ")) {
        const metadata = body.split(": ")[0]!;
        for (const [field, pattern] of uploadFields) {
            const value = pattern.exec(metadata)?.[1];
            if (value) details.push(`${field}=${value}`);
        }
    }
    if (event == "[rust] ente_core::http: retrying") {
        const delay =
            /(?:retrying in |delaySeconds=)(2|5|10|30|120)(?:s|\b)/.exec(
                body,
            )?.[1];
        if (delay) details.push(`delaySeconds=${delay}`);
    }
    const exitCode =
        /(?:ffmpeg command failed with exit code |ffprobe command failed with exit code |exitCode=)(-?\d{1,3})\b/.exec(
            body,
        )?.[1];
    if (exitCode) details.push(`exitCode=${exitCode}`);
    const status = /(?:HTTP |status=)([45]\d{2})\b/.exec(body)?.[1];
    if (status) details.push(`status=${status}`);
    const code = errorCodes.find((code) => body.includes(code));
    if (code) details.push(`code=${code}`);
    const reason = errorReasons.find((reason) => body.includes(reason));
    if (reason) details.push(`reason=${reason}`);
    return details.join(" ");
};
