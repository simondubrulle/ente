import { getPasskeyCount } from "ente-accounts/services/passkey";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.photos.web",
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string) => Promise.resolve(path),
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () =>
        Promise.resolve({ "X-Auth-Token": "photos-token" }),
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-accounts/services/accounts-db", () => ({}));
vi.mock("ente-accounts/services/user", () => ({}));
vi.mock("ente-accounts/services/redirect", () => ({}));

afterEach(() => vi.unstubAllGlobals());

test.each([
    [[{ id: "key-1" }], 1],
    [null, 0],
    [[], 0],
])(
    "counts passkeys using an Accounts token: %j",
    async (passkeys, expected) => {
        const fetchMock = vi
            .fn()
            .mockResolvedValueOnce(
                Response.json({
                    accountsToken: "accounts-token",
                    accountsUrl: "https://accounts.ente.io",
                }),
            )
            .mockResolvedValueOnce(
                Response.json({
                    passkeys,
                    accountsUrl: "https://accounts.ente.io",
                }),
            );
        vi.stubGlobal("fetch", fetchMock);
        expect(await getPasskeyCount()).toBe(expected);
        expect(fetchMock).toHaveBeenNthCalledWith(1, "/users/accounts-token", {
            headers: { "X-Auth-Token": "photos-token" },
        });
        expect(fetchMock).toHaveBeenNthCalledWith(2, "/passkeys", {
            headers: {
                "X-Auth-Token": "accounts-token",
                "X-Client-Package": "io.ente.photos.web",
            },
        });
    },
);
