import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { createSpaceVideoContent } from "../src/components/PostVideoContent";
import type {
    SpacePostAsset,
    SpacePostAssetURLLoader,
} from "../src/services/space";

vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));

class Element extends EventTarget {
    style = {};
    attributes = new Map<string, string>();
    children: Element[] = [];
    disabled = false;
    hidden = false;
    setAttribute(name: string, value: string) {
        this.attributes.set(name, value);
    }
    getAttribute(name: string) {
        return this.attributes.get(name) ?? null;
    }
    removeAttribute(name: string) {
        this.attributes.delete(name);
    }
    append(...children: Element[]) {
        this.children.push(...children);
    }
}

class Video extends Element {
    preload = "none";
    paused = true;
    ended = false;
    currentTime = 0;
    onpause?: () => void;
    onplaying?: () => void;
    set src(value: string) {
        this.setAttribute("src", value);
    }
    play = vi.fn(() => {
        this.paused = false;
        this.onplaying?.();
        return Promise.resolve();
    });
    pause() {
        if (this.paused) return;
        this.paused = true;
        this.onpause?.();
    }
    load = vi.fn();
}

let contents: ReturnType<typeof createSpaceVideoContent>[];
let load: ReturnType<typeof vi.fn<SpacePostAssetURLLoader>>;
let revokeURL: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
    vi.useFakeTimers();
    contents = [];
    load = vi.fn<SpacePostAssetURLLoader>().mockResolvedValue("blob:video");
    revokeURL = vi
        .spyOn(URL, "revokeObjectURL")
        .mockImplementation(() => undefined);
    vi.stubGlobal(
        "document",
        Object.assign(new EventTarget(), {
            hidden: false,
            createElement: (tag: string) =>
                tag == "video" ? new Video() : new Element(),
        }),
    );
});

afterEach(() => {
    contents.forEach((content) => content.destroy());
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

const create = (inline = true) => {
    const content = createSpaceVideoContent(
        {
            imageUrl: "blob:poster",
            video: {
                asset: { objectKey: "video" } as SpacePostAsset,
                durationMs: 1000,
            },
        },
        load,
        { inline },
    );
    contents.push(content);
    const [video, button, loading, error] = (
        content.element as unknown as Element
    ).children;
    return {
        ...content,
        video: video as Video,
        button: button!,
        loading: loading!,
        error: error!,
    };
};

test("background preload keeps the poster controls hidden and does not play", async () => {
    const content = create();
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
    await content.preload();
    expect(content.video.getAttribute("src")).toBe("blob:video");
    expect(content.video.preload).toBe("auto");
    expect(content.video.play).not.toHaveBeenCalled();
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
    expect(content.loading.getAttribute("aria-hidden")).toBe("true");
    expect(content.element.getAttribute("aria-busy")).toBeNull();
});

test("autoplay joins an in-flight preload without downloading the video again", async () => {
    const download = Promise.withResolvers<string>();
    load.mockReturnValue(download.promise);
    const content = create();
    const preload = content.preload();
    content.play();
    expect(load).toHaveBeenCalledTimes(1);
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
    download.resolve("blob:video");
    await preload;
    await vi.advanceTimersByTimeAsync(0);
    expect(content.video.play).toHaveBeenCalledTimes(1);
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
});

test("the play button appears on pause and hides immediately on resume", async () => {
    const content = create();
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    content.pause();
    expect(content.button.getAttribute("aria-hidden")).toBe("false");
    content.play();
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
    await vi.advanceTimersByTimeAsync(0);
    expect(content.video.paused).toBe(false);
    expect(load).toHaveBeenCalledTimes(1);
});

test("switching carousel slides preserves the loaded video for its next activation", async () => {
    const content = create();
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    content.deactivate();
    expect(content.video.paused).toBe(true);
    expect(revokeURL).not.toHaveBeenCalled();
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    expect(load).toHaveBeenCalledTimes(1);
    expect(content.video.play).toHaveBeenCalledTimes(2);
});

test("deactivating during a download keeps the preload without starting playback", async () => {
    const download = Promise.withResolvers<string>();
    load.mockReturnValue(download.promise);
    const content = create();
    const preload = content.preload();
    content.play();
    content.deactivate();
    download.resolve("blob:video");
    await preload;
    await vi.advanceTimersByTimeAsync(0);
    expect(content.video.play).not.toHaveBeenCalled();
    expect(revokeURL).not.toHaveBeenCalled();
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    expect(load).toHaveBeenCalledTimes(1);
    expect(content.video.play).toHaveBeenCalledTimes(1);
});

test("leaving the preload range releases a completed video", async () => {
    const content = create();
    await content.preload();
    content.destroy();
    expect(revokeURL).toHaveBeenCalledExactlyOnceWith("blob:video");
    expect(content.video.getAttribute("src")).toBeNull();
});

test("leaving the preload range releases a download that finishes later", async () => {
    const download = Promise.withResolvers<string>();
    load.mockReturnValue(download.promise);
    const content = create();
    const preload = content.preload();
    content.destroy();
    download.resolve("blob:late");
    await preload;
    expect(revokeURL).toHaveBeenCalledExactlyOnceWith("blob:late");
    expect(content.video.getAttribute("src")).toBeNull();
    expect(content.video.play).not.toHaveBeenCalled();
});

test("a failed background preload can be retried by playback", async () => {
    load.mockRejectedValueOnce(new Error("offline"));
    const content = create();
    await expect(content.preload()).rejects.toThrow("offline");
    expect(content.error.hidden).toBe(true);
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    expect(load).toHaveBeenCalledTimes(2);
    expect(content.video.paused).toBe(false);
});

test("a timed-out download cannot replace the source after retry", async () => {
    const download = Promise.withResolvers<string>();
    load.mockReturnValueOnce(download.promise);
    const content = create();
    content.play();
    await vi.advanceTimersByTimeAsync(30_000);
    expect(content.error.hidden).toBe(false);
    expect(content.button.getAttribute("aria-hidden")).toBe("false");
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    download.resolve("blob:late");
    await vi.advanceTimersByTimeAsync(0);
    expect(content.video.getAttribute("src")).toBe("blob:video");
    expect(content.video.play).toHaveBeenCalledTimes(1);
    expect(revokeURL).toHaveBeenCalledWith("blob:late");
});

test("fullscreen video still releases its source on deactivation", async () => {
    const content = create(false);
    content.play();
    await vi.advanceTimersByTimeAsync(0);
    content.deactivate();
    expect(content.video.paused).toBe(true);
    expect(content.video.getAttribute("src")).toBeNull();
    expect(revokeURL).toHaveBeenCalledExactlyOnceWith("blob:video");
    expect(content.button.getAttribute("aria-hidden")).toBe("true");
});
