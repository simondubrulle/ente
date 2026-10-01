import { defineConfig } from "vitest/config";

export default defineConfig({
    test: {},
    oxc: { jsx: { runtime: "automatic" } },
});
