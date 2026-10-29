import { generateKey } from "ente-base/crypto";
import { CollectionSubType, type Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    hideFiles,
    movePendingRemovalActionsToUncategorized,
} from "ente-new/photos/services/collection";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => import("ente-base/crypto/libsodium"));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-new/photos/services/account-keys", () => ({
    ensureMasterKeyFromSession: () => {
        throw new Error("Creation attempted");
    },
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({
    savedCollections: vi.fn(),
    savedCollectionFiles: vi.fn(),
}));
vi.mock("ente-base/http", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/http")>()),
    authenticatedRequestHeaders: () => Promise.resolve({}),
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string) => Promise.resolve(`https://example.invalid${path}`),
}));

const fetchMock = vi.fn();
beforeEach(() => {
    vi.stubGlobal("window", {});
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockImplementation((url: string) => {
        if (url.endsWith("/collection-actions/pending-remove")) {
            return Promise.resolve(
                Response.json({ actions: [{ collectionID: 10, fileID: 100 }] }),
            );
        }
        return Promise.resolve(new Response(null, { status: 200 }));
    });
});
afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetAllMocks();
});

const hiddenAlbum = async (
    id: number,
    ownerID: number,
): Promise<Collection> => ({
    id,
    owner: { id: ownerID },
    key: await generateKey(),
    name: ".hidden",
    type: "album",
    sharees: [],
    publicURLs: [],
    updationTime: 1,
    magicMetadata: {
        version: 1,
        count: 2,
        data: {
            subType: CollectionSubType.defaultHidden,
            visibility: ItemVisibility.hidden,
        },
    },
});

test.each([
    ["hide", true],
    ["hide", false],
    ["pending removal", true],
    ["pending removal", false],
] as const)(
    "%s selects only owned Hidden albums (owned exists: %s)",
    async (flow, hasOwned) => {
        const foreign = await hiddenAlbum(2, 2);
        const oldestOwned = await hiddenAlbum(20, 1);
        const newerOwned = await hiddenAlbum(30, 1);
        const source = await hiddenAlbum(10, 1);
        delete source.magicMetadata!.data.subType;
        const collections = [
            foreign,
            ...(hasOwned ? [newerOwned, oldestOwned] : []),
            source,
        ];
        const file = {
            id: 100,
            collectionID: source.id,
            key: await generateKey(),
        } as EnteFile;
        vi.mocked(savedCollections).mockResolvedValue(collections);
        vi.mocked(savedCollectionFiles).mockResolvedValue([file]);

        const result =
            flow == "hide"
                ? hideFiles([file])
                : movePendingRemovalActionsToUncategorized(collections);

        if (!hasOwned) {
            await expect(result).rejects.toThrow("Creation attempted");
            expect(
                fetchMock.mock.calls.some(([url]) =>
                    (url as string).endsWith("/collections/move-files"),
                ),
            ).toBe(false);
            return;
        }

        await result;
        const move = fetchMock.mock.calls.find(([url]) =>
            (url as string).endsWith("/collections/move-files"),
        )!;
        expect(
            JSON.parse((move[1] as RequestInit).body as string),
        ).toMatchObject({
            fromCollectionID: source.id,
            toCollectionID: oldestOwned.id,
            files: [{ id: file.id }],
        });
    },
);
