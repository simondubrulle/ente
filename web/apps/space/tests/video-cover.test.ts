import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    spaceVideoCover,
    spaceVideoFrames,
    spaceVideoInfo,
} from "../src/utils/post-video";

const mocks = vi.hoisted(() => ({
    frames: vi.fn(),
    info: vi.fn(),
    log: vi.fn(),
}));
vi.mock("../src/utils/video-encoding/web", () => ({
    extractVideoFramesWeb: mocks.frames,
    determineVideoInfoWeb: mocks.info,
}));
vi.mock("ente-base/log-web", () => ({ logToDisk: mocks.log }));
vi.mock("utils/thumbhash", () => ({ thumbHashBase64FromCanvas: () => "hash" }));

let alpha: number;
let bitmapClose: ReturnType<typeof vi.fn>;
let createElement: ReturnType<typeof vi.fn>;

beforeEach(() => {
    vi.resetAllMocks();
    alpha = 255;
    bitmapClose = vi.fn();
    vi.stubGlobal("navigator", {
        userAgent:
            "Mozilla/5.0 (Android 16; Mobile; rv:143.0) Gecko/143.0 Firefox/143.0",
    });
    mocks.frames.mockResolvedValue([new Blob(["png"], { type: "image/png" })]);
    mocks.info.mockResolvedValue({ duration: 3.45, width: 1080, height: 1920 });
    vi.stubGlobal(
        "createImageBitmap",
        vi
            .fn()
            .mockImplementation(() =>
                Promise.resolve({
                    width: 540,
                    height: 960,
                    close: bitmapClose,
                }),
            ),
    );
    createElement = vi.fn((tag: string) => {
        if (tag != "canvas")
            throw new Error(
                "Must not decode through a video element on Firefox Android",
            );
        return {
            width: 0,
            height: 0,
            getContext: () => ({
                drawImage: vi.fn(),
                getImageData: () => ({
                    data: new Uint8ClampedArray([0, 0, 0, alpha]),
                }),
            }),
            toBlob: (callback: BlobCallback) =>
                callback(new Blob(["cover"], { type: "image/webp" })),
        };
    });
    vi.stubGlobal("document", { createElement });
});
afterEach(() => vi.unstubAllGlobals());

test.each([
    [
        "Mozilla/5.0 (Android 16; Mobile; rv:143.0) Gecko/143.0 Firefox/143.0",
        true,
    ],
    ["Mozilla/5.0 (Android 16) Chrome/140.0.0.0 Mobile Safari/537.36", false],
    [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0",
        false,
    ],
])(
    "selects software frames only for Firefox Android (%s)",
    async (userAgent, software) => {
        vi.stubGlobal("navigator", { userAgent });
        if (!software) {
            vi.stubGlobal("window", { setTimeout, clearTimeout });
            const video = Object.assign(new EventTarget(), {
                duration: 3.45,
                videoWidth: 540,
                videoHeight: 960,
                currentTime: 0,
                pause: vi.fn(),
                removeAttribute: vi.fn(),
                load: () => video.dispatchEvent(new Event("loadeddata")),
            });
            createElement.mockImplementationOnce(() => video);
        }
        const file = new Blob(["video"]);
        expect(await spaceVideoFrames(file, [0], 960)).toHaveLength(1);
        expect(mocks.frames).toHaveBeenCalledTimes(software ? 1 : 0);
        expect(createElement).toHaveBeenCalledWith(
            software ? "canvas" : "video",
        );
    },
);

test("Firefox Android gets metadata and a cover without creating a video element", async () => {
    const file = new File(["video"], "private-video.mp4");
    const controller = new AbortController();
    expect(await spaceVideoInfo(file, controller.signal)).toMatchObject({
        width: 1080,
        height: 1920,
    });
    const cover = await spaceVideoCover(file, 1.25, controller.signal);
    expect(mocks.frames).toHaveBeenCalledWith(
        file,
        [1.25],
        960,
        controller.signal,
    );
    expect(cover).toMatchObject({ width: 540, height: 960, thumbHash: "hash" });
    expect(cover.file.type).toBe("image/webp");
    expect(bitmapClose).toHaveBeenCalledOnce();
    expect(JSON.stringify(mocks.log.mock.calls)).not.toContain("private-video");
});

test("opaque black frames are valid covers, but unreadable transparent frames fail", async () => {
    const file = new Blob(["video"]);
    await expect(spaceVideoCover(file, 0)).resolves.toBeDefined();
    alpha = 0;
    await expect(spaceVideoCover(file, 0)).rejects.toThrow(
        "Couldn't read a video frame",
    );
    expect(bitmapClose).toHaveBeenCalledTimes(2);
    expect(mocks.log).toHaveBeenCalledWith(
        expect.stringContaining("frames failed backend=wasm"),
    );
});

test("timeline frame extraction is batched and releases each decoded image", async () => {
    const file = new Blob(["video"]);
    const times = [0.5, 1.5, 2.5];
    mocks.frames.mockResolvedValue(times.map(() => new Blob(["png"])));
    expect(await spaceVideoFrames(file, times, 128)).toHaveLength(3);
    expect(mocks.frames).toHaveBeenCalledWith(file, times, 128, undefined);
    expect(bitmapClose).toHaveBeenCalledTimes(3);
});

test("canceling frame extraction does not leave decoded bitmaps or return a cover", async () => {
    const controller = new AbortController();
    mocks.frames.mockImplementation(() => {
        controller.abort();
        return Promise.resolve([new Blob(["png"])]);
    });
    await expect(
        spaceVideoCover(new Blob(["video"]), 0, controller.signal),
    ).rejects.toMatchObject({ name: "AbortError" });
    expect(createImageBitmap).not.toHaveBeenCalled();
});
