import { buildEnvAccountsOrigin } from "./env";

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
 * Use the configured Accounts origin, or the hosted origins for current and
 * legacy passkeys. Local HTTP is allowed only when explicitly configured.
 */
export const accountsNavigationURL = (value: string): URL =>
    trustedNavigationURL(
        value,
        buildEnvAccountsOrigin
            ? [new URL(buildEnvAccountsOrigin).origin]
            : ["https://accounts.ente.com", "https://accounts.ente.io"],
        !!buildEnvAccountsOrigin,
    );
