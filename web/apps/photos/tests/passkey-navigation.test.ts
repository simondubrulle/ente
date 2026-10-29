import {
    openAccountsManagePasskeysPage,
    openPasskeyVerificationURL,
    passkeyVerificationRedirectURL,
} from "ente-accounts/services/passkey";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("ente-accounts/services/accounts-db", () => ({}));
vi.mock("ente-accounts/services/user", () => ({}));
vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.photos",
    isDesktop: false,
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: vi.fn(),
    ensureOk: vi.fn(),
}));
vi.mock("ente-base/origins", () => ({ apiURL: (path: string) => path }));
vi.mock("ente-base/env", () => ({
    isDevBuild: false,
    buildEnvAccountsOrigin: undefined,
}));
vi.mock("ente-accounts/services/redirect", () => ({}));

const maliciousURL = "javascript:alert(sessionStorage.keyEncryptionKey)//";
const setItem = vi.fn();
const open = vi.fn();
const location = { origin: "https://photos.ente.com", href: "" };

beforeEach(() => {
    location.href = "";
    vi.stubGlobal("window", { location, open });
    vi.stubGlobal("sessionStorage", { setItem });
});
afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
});

test("rejects the reported payload before constructing a login redirect", () => {
    expect(() =>
        passkeyVerificationRedirectURL(maliciousURL, "session"),
    ).toThrow();
});

test.each(["https://accounts.ente.com", "https://accounts.ente.io/"])(
    "preserves login parameters for %s",
    (base) => {
        const url = new URL(
            passkeyVerificationRedirectURL(base, "session & id"),
        );
        expect(url.pathname).toBe("/passkeys/verify");
        expect(url.searchParams.get("passkeySessionID")).toBe("session & id");
        expect(url.searchParams.get("redirect")).toBe(
            "https://photos.ente.com/passkeys/finish",
        );
        expect(url.searchParams.get("recover")).toBe(
            "https://photos.ente.com/passkeys/recover",
        );
    },
);

test.each([false, true])(
    "rejects unsafe navigation with electron=%s",
    (desktop) => {
        vi.stubGlobal("electron", desktop ? {} : undefined);
        expect(() =>
            openPasskeyVerificationURL({
                passkeySessionID: "session",
                url: maliciousURL,
            }),
        ).toThrow();
        expect(setItem).not.toHaveBeenCalled();
        expect(open).not.toHaveBeenCalled();
        expect(location.href).toBe("");
    },
);

test.each([false, true])(
    "opens a valid login URL with electron=%s",
    (desktop) => {
        vi.stubGlobal("electron", desktop ? {} : undefined);
        const url = passkeyVerificationRedirectURL(
            "https://accounts.ente.com",
            "session",
        );
        openPasskeyVerificationURL({ passkeySessionID: "session", url });
        expect(setItem).toHaveBeenCalledWith(
            "inflightPasskeySessionID",
            "session",
        );
        if (desktop) expect(open).toHaveBeenCalledWith(url);
        else expect(location.href).toBe(url);
    },
);

test.each([maliciousURL, "https://evil.example"])(
    "rejects an unsafe management destination %s",
    async (accountsUrl) => {
        vi.stubGlobal(
            "fetch",
            vi
                .fn()
                .mockResolvedValueOnce({
                    json: () =>
                        Promise.resolve({ isPasskeyRecoveryEnabled: true }),
                })
                .mockResolvedValueOnce({
                    json: () =>
                        Promise.resolve({
                            accountsUrl,
                            accountsToken: "token",
                        }),
                }),
        );
        await expect(openAccountsManagePasskeysPage(vi.fn())).rejects.toThrow();
        expect(open).not.toHaveBeenCalled();
    },
);

test("opens the trusted management URL with encoded token parameters", async () => {
    vi.stubGlobal(
        "fetch",
        vi
            .fn()
            .mockResolvedValueOnce({
                json: () => Promise.resolve({ isPasskeyRecoveryEnabled: true }),
            })
            .mockResolvedValueOnce({
                json: () =>
                    Promise.resolve({
                        accountsUrl:
                            "https://accounts.ente.com/?ignored=true#old",
                        accountsToken: "token & value",
                    }),
            }),
    );
    await openAccountsManagePasskeysPage(vi.fn());
    const url = new URL(open.mock.calls[0]![0] as string);
    expect(url.origin).toBe("https://accounts.ente.com");
    expect(url.pathname).toBe("/passkeys");
    expect(url.searchParams.get("token")).toBe("token & value");
    expect(url.searchParams.has("ignored")).toBe(false);
    expect(url.hash).toBe("");
});
