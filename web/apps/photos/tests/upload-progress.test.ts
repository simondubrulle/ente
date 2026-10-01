import { ThemeProvider } from "@mui/material/styles";
import { photosTheme } from "ente-base/components/utils/theme";
import translation from "ente-base/locales/en-US/translation.json";
import type { SegregatedFinishedUploads } from "ente-gallery/components/upload-progress-stats";
import {
    UploadProgressContext,
    type UploadProgressContextT,
} from "ente-gallery/components/upload-progress/context";
import { uploadCountsText } from "ente-gallery/components/upload-progress/helpers";
import { MinimizedUploadProgress } from "ente-gallery/components/upload-progress/MinimizedUploadProgress";
import i18n from "i18next";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeAll, expect, test } from "vitest";

beforeAll(async () => {
    await i18n.init({
        lng: "en-US",
        resources: { "en-US": { translation } },
        interpolation: { escapeValue: false },
    });
});

const context: UploadProgressContextT = {
    onClose: () => undefined,
    uploadCounter: { finished: 0, total: 0 },
    uploadPhase: "done",
    percentComplete: 100,
    retryFailed: () => undefined,
    inProgressUploads: [],
    uploadFileNames: new Map(),
    finishedUploads: new Map(),
    preUploadSkippedFiles: [],
    hasLivePhotos: false,
    setExpanded: () => undefined,
    dragPosition: undefined,
    setDragPosition: () => undefined,
};

const renderProgress = (value: UploadProgressContextT) =>
    renderToStaticMarkup(
        createElement(
            ThemeProvider,
            { theme: photosTheme },
            createElement(
                UploadProgressContext.Provider,
                { value },
                createElement(MinimizedUploadProgress),
            ),
        ),
    );

test.each(["failed", "blocked"] as const)(
    "%s uploads show failure text and a red popup",
    (type) => {
        const value = { ...context, finishedUploads: new Map([[type, [1]]]) };
        expect(uploadCountsText(value)).toBe("1 failed");
        const html = renderProgress(value);
        expect(html).toContain(">Failed uploads<");
        expect(html).toContain(">1 failed<");
        expect(html).not.toContain(">Upload complete<");
        expect(html).toContain(
            "background-color:var(--mui-palette-critical-main)",
        );
    },
);

test("mixed results keep completed, skipped, and failed counts separate", () => {
    const finishedUploads: SegregatedFinishedUploads = new Map([
        ["uploaded", [1, 2]],
        ["alreadyUploaded", [3]],
        ["failed", [4]],
        ["blocked", [5]],
    ]);
    const value = { ...context, finishedUploads };
    expect(uploadCountsText(value)).toBe("2 uploaded, 1 skipped, 2 failed");
    expect(renderProgress(value)).toContain(
        ">2 uploaded, 1 skipped, 2 failed<",
    );
});

test("failures remain visible while other files are still uploading", () => {
    const value: UploadProgressContextT = {
        ...context,
        uploadPhase: "uploading",
        uploadCounter: { finished: 2, total: 4 },
        finishedUploads: new Map([["failed", [1]]]),
    };
    expect(uploadCountsText(value)).toBe("2 of 4 items, 1 failed");
    expect(renderProgress(value)).toContain(
        "background-color:var(--mui-palette-critical-main)",
    );
});

test("ordinary skips keep the neutral popup and their own count", () => {
    const value: UploadProgressContextT = {
        ...context,
        finishedUploads: new Map([
            ["alreadyUploaded", [1]],
            ["unsupported", [2]],
        ]),
        preUploadSkippedFiles: [{ type: "hiddenFile", name: ".hidden.jpg" }],
    };
    expect(uploadCountsText(value)).toBe("3 skipped");
    const html = renderProgress(value);
    expect(html).toContain(">Upload complete<");
    expect(html).not.toContain(
        "background-color:var(--mui-palette-critical-main)",
    );
});

test("a successful retry clears the failure title and red popup", () => {
    const value: UploadProgressContextT = {
        ...context,
        finishedUploads: new Map([["failed", [1]]]),
    };
    expect(renderProgress(value)).toContain(">Failed uploads<");
    value.finishedUploads = new Map([["uploaded", [1]]]);
    expect(uploadCountsText(value)).toBe("1 uploaded");
    const html = renderProgress(value);
    expect(html).toContain(">Upload complete<");
    expect(html).toContain(">1 uploaded<");
    expect(html).not.toContain(
        "background-color:var(--mui-palette-critical-main)",
    );
});
