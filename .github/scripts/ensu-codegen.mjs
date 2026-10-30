#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
);
execFileSync(process.execPath, [path.join(root, "desktop/scripts/ort.js")], {
    cwd: root,
    stdio: "inherit",
});

const runtime = path.join(
    root,
    "desktop/node_modules/.cache/ente-onnxruntime",
    process.arch,
);
const loaderPath =
    process.platform === "darwin"
        ? "DYLD_LIBRARY_PATH"
        : process.platform === "win32"
          ? "PATH"
          : "LD_LIBRARY_PATH";
execFileSync("cargo", ["codegen", "native", "ensu"], {
    cwd: path.join(root, "rust"),
    stdio: "inherit",
    env: {
        ...process.env,
        ORT_LIB_PATH: runtime,
        ORT_PREFER_DYNAMIC_LINK: "1",
        [loaderPath]: [runtime, process.env[loaderPath]]
            .filter(Boolean)
            .join(path.delimiter),
    },
});
