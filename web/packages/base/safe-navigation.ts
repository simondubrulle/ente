/** Parse a navigation URL and allow only HTTP or HTTPS. */
export const httpOrHTTPSURL = (value: string): URL => {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
        throw new Error("Unsupported navigation URL protocol");
    }
    return url;
};
