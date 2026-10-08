const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const StreamZip = require("node-stream-zip");

const release = "9.0.2";
const checksums = {
    "darwin-universal":
        "ba2f10d5433ae4b22f482ea2cee85d50819455e1e63b5aa1ecf6201ad2f2b7c9",
    "linux-x64":
        "7cf14c99d674d5f2ad2897f83f2b00307f66dba6c2f4fa854601a0521bc47886",
    "linux-arm64":
        "00dd72f0f0ac4805d90b3c01a667909f04d6f821f90189791e1dea59cf8507ba",
    "windows-x64":
        "0d772b1676871c480a8f140c45507c68e3077013d42792088c8db55f1611aba2",
    "windows-arm64":
        "4f6df97fcd471adeac97079e271617e0fee322610faeca89f6590c323a5af654",
};

const ensureFFmpeg = async (platform, arch, appDir) => {
    const target =
        platform == "darwin"
            ? "darwin-universal"
            : `${platform == "win32" ? "windows" : platform}-${arch}`;
    const expected = checksums[target];
    if (!expected) throw new Error(`No pinned FFmpeg archive for ${target}`);

    const out = path.join(appDir, "build", "ffmpeg");
    const stamp = path.join(out, ".archive-sha256");
    const binaries = ["ffmpeg", "ffprobe"].map((name) =>
        platform == "win32" ? `${name}.exe` : name,
    );
    try {
        if ((await fs.readFile(stamp, "utf8")) == expected) {
            await Promise.all(
                binaries.map((name) => fs.access(path.join(out, name))),
            );
            return;
        }
    } catch (e) {
        if (e.code != "ENOENT") throw e;
    }

    const asset = `${target}-ffmpeg.${platform == "win32" ? "zip" : "tar.gz"}`;
    console.log(`Downloading ${asset} (${release})`);
    const response = await fetch(
        `https://github.com/ente/ffmpeg-packaging/releases/download/${release}/${asset}`,
    );
    if (!response.ok)
        throw new Error(`Failed to download ${asset}: HTTP ${response.status}`);
    const archive = Buffer.from(await response.arrayBuffer());
    const actual = crypto.createHash("sha256").update(archive).digest("hex");
    if (actual != expected)
        throw new Error(`SHA-256 mismatch for ${asset}: ${actual}`);

    await fs.mkdir(path.dirname(out), { recursive: true });
    const stage = await fs.mkdtemp(path.join(path.dirname(out), ".ffmpeg-"));
    try {
        const archivePath = path.join(stage, asset);
        await fs.writeFile(archivePath, archive);
        if (platform == "win32") {
            const zip = new StreamZip.async({ file: archivePath });
            try {
                await zip.extract(null, stage);
            } finally {
                await zip.close();
            }
        } else {
            execFileSync("tar", ["-xf", archivePath, "-C", stage]);
        }
        await fs.unlink(archivePath);
        for (const name of binaries)
            await fs.chmod(path.join(stage, name), 0o755);
        await fs.writeFile(path.join(stage, ".archive-sha256"), expected);
        await fs.rm(out, { recursive: true, force: true });
        await fs.rename(stage, out);
    } finally {
        await fs.rm(stage, { recursive: true, force: true });
    }
};

module.exports = { ensureFFmpeg };

if (require.main === module)
    ensureFFmpeg(
        process.platform,
        process.arch,
        path.resolve(__dirname, ".."),
    ).catch((e) => {
        console.error(e);
        process.exit(1);
    });
