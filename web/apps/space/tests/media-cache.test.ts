import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    cachedSpaceMediaBlobURL,
    clearSpaceMediaURLCache,
    spacePostMediaCacheKey,
    spaceProfileMediaCacheKey,
} from "../src/services/media-cache";
import { SpaceMediaRateLimitError } from "../src/services/media-load";

vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("https://api.example.com"),
}));
vi.mock("ente-base/blob-cache", () => ({
    blobCache: () => Promise.resolve({ get: () => undefined, put: vi.fn() }),
}));

const assets = [
    { key: spaceProfileMediaCacheKey("space", "avatar", "avatar", 1) },
    { key: spaceProfileMediaCacheKey("space", "cover", "cover", 1) },
    { key: spacePostMediaCacheKey("space", "photo") },
    { key: spacePostMediaCacheKey("space", "video"), mediaType: "video/mp4" },
];

beforeEach(() => {
    vi.useFakeTimers();
    clearSpaceMediaURLCache();
    vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:media");
    vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => undefined);
});

afterEach(() => {
    clearSpaceMediaURLCache();
    vi.restoreAllMocks();
    vi.useRealTimers();
});

test.each(assets)(
    "a 429 from $key pauses all uncached media downloads",
    async (asset) => {
        const download = vi.fn().mockResolvedValue(new Uint8Array([1]));
        await cachedSpaceMediaBlobURL("cached-photo", download);
        download.mockClear();
        const failure = await cachedSpaceMediaBlobURL(
            asset.key,
            () =>
                Promise.reject(
                    Object.assign(new Error("Rate limit"), { status: 429 }),
                ),
            asset.mediaType,
        ).catch((error: unknown) => error);
        expect(failure).toBeInstanceOf(SpaceMediaRateLimitError);

        await vi.advanceTimersByTimeAsync(59_999);
        for (const other of assets) {
            await expect(
                cachedSpaceMediaBlobURL(other.key, download, other.mediaType),
            ).rejects.toBe(failure);
        }
        await expect(
            cachedSpaceMediaBlobURL("cached-photo", download),
        ).resolves.toBe("blob:media");
        expect(download).not.toHaveBeenCalled();

        await vi.advanceTimersByTimeAsync(1);
        for (const other of assets) {
            await expect(
                cachedSpaceMediaBlobURL(other.key, download, other.mediaType),
            ).resolves.toBe("blob:media");
        }
        expect(download).toHaveBeenCalledTimes(assets.length);
    },
);
