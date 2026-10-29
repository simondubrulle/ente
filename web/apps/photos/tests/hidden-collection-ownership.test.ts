import { decryptBox, generateKey } from "ente-base/crypto";
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
    ensureMasterKeyFromSession: () => generateKey(),
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
        if (url.endsWith("/collections")) {
            throw new Error("Creation attempted");
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

const flows = ["hide", "pending removal"] as const;
type Flow = (typeof flows)[number];

async function runFlow(flow: Flow, collections: Collection[], file: EnteFile) {
    vi.mocked(savedCollections).mockResolvedValue(collections);
    vi.mocked(savedCollectionFiles).mockResolvedValue([file]);
    if (flow == "hide") await hideFiles([file]);
    else await movePendingRemovalActionsToUncategorized(collections);
}

test.each(flows)("%s preserves the normal owned destination", async (flow) => {
    const source = await hiddenAlbum(10, 1);
    delete source.magicMetadata!.data.subType;
    const destination = await hiddenAlbum(20, 1);
    const collections = [source, destination];
    const before = structuredClone(collections);
    const file = {
        id: 100,
        collectionID: source.id,
        ownerID: 1,
        key: await generateKey(),
    } as EnteFile;

    await runFlow(flow, collections, file);

    const move = fetchMock.mock.calls.find(([url]) =>
        (url as string).endsWith("/collections/move-files"),
    )!;
    expect(JSON.parse((move[1] as RequestInit).body as string)).toMatchObject({
        fromCollectionID: source.id,
        toCollectionID: destination.id,
        files: [{ id: file.id }],
    });
    expect(collections).toEqual(before);
    expect(fetchMock).toHaveBeenCalledTimes(flow == "hide" ? 1 : 2);
});

test("hiding a file already in the owned Hidden album remains a no-op", async () => {
    const destination = await hiddenAlbum(10, 1);
    const file = {
        id: 100,
        collectionID: destination.id,
        ownerID: 1,
        key: await generateKey(),
    } as EnteFile;

    await runFlow("hide", [destination], file);

    expect(fetchMock).not.toHaveBeenCalled();
});

test.each(flows)(
    "%s uses the oldest owned Hidden album and keeps file keys secret from a foreign album",
    async (flow) => {
        const foreign = await hiddenAlbum(2, 2);
        const newerOwned = await hiddenAlbum(30, 1);
        const oldestOwned = await hiddenAlbum(20, 1);
        const source = await hiddenAlbum(10, 1);
        delete source.magicMetadata!.data.subType;
        const file = {
            id: 100,
            collectionID: source.id,
            ownerID: 1,
            key: await generateKey(),
        } as EnteFile;

        await runFlow(flow, [foreign, newerOwned, oldestOwned, source], file);

        const move = fetchMock.mock.calls.find(([url]) =>
            (url as string).endsWith("/collections/move-files"),
        )!;
        const payload = JSON.parse((move[1] as RequestInit).body as string) as {
            toCollectionID: number;
            files: {
                id: number;
                encryptedKey: string;
                keyDecryptionNonce: string;
            }[];
        };
        const item = payload.files[0]!;
        const box = {
            encryptedData: item.encryptedKey,
            nonce: item.keyDecryptionNonce,
        };
        await expect(decryptBox(box, foreign.key)).rejects.toThrow();
        expect(payload.toCollectionID).toBe(oldestOwned.id);
        expect(item.id).toBe(file.id);
        expect(await decryptBox(box, oldestOwned.key)).toBe(file.key);
    },
);

test.each(flows)(
    "%s creates an owned Hidden album when only a foreign default exists",
    async (flow) => {
        const foreign = await hiddenAlbum(2, 2);
        const source = await hiddenAlbum(10, 1);
        delete source.magicMetadata!.data.subType;
        const file = {
            id: 100,
            collectionID: source.id,
            ownerID: 1,
            key: await generateKey(),
        } as EnteFile;

        await expect(runFlow(flow, [foreign, source], file)).rejects.toThrow(
            "Creation attempted",
        );
        expect(
            fetchMock.mock.calls.some(([url]) =>
                (url as string).endsWith("/collections/move-files"),
            ),
        ).toBe(false);
    },
);
