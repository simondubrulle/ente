import { buildEnvAccountsOrigin, isDevBuild } from "./env";

/** Parse an absolute server-supplied URL before using it as a destination. */
export const trustedNavigationURL = (
    value: string,
    trustedOrigins: readonly string[],
    allowLocalHTTP = false,
): URL => {
    const url = new URL(value);
    const isLocalHTTP =
        allowLocalHTTP &&
        url.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (
        (url.protocol !== "https:" && !isLocalHTTP) ||
        url.username ||
        url.password ||
        !trustedOrigins.includes(url.origin)
    ) {
        throw new Error("Untrusted navigation URL");
    }
    return url;
};

/**
 * Trust the client build's Accounts origin, never an API-selected origin.
 * Both hosted origins are needed during the legacy passkey RP migration.
 * Local HTTP requires an explicit build override and a development build.
 */
export const accountsNavigationURL = (value: string): URL =>
    trustedNavigationURL(
        value,
        buildEnvAccountsOrigin
            ? [new URL(buildEnvAccountsOrigin).origin]
            : ["https://accounts.ente.com", "https://accounts.ente.io"],
        isDevBuild && !!buildEnvAccountsOrigin,
    );
