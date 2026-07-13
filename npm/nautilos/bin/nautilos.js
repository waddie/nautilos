#!/usr/bin/env node
// Launcher: resolve the platform-specific nautilos binary (installed as an
// optional dependency for this OS/arch) and exec it, passing through args,
// stdio and the exit code.
"use strict";

const { spawnSync } = require("child_process");

const OS = { darwin: "darwin", linux: "linux" };
const ARCH = { arm64: "arm64", x64: "x64" };

const os = OS[process.platform];
const arch = ARCH[process.arch];

if (!os || !arch) {
  console.error(
    `nautilos: unsupported platform ${process.platform}-${process.arch}; ` +
      "prebuilt binaries cover darwin/linux on arm64/x64. Build from source: " +
      "https://github.com/waddie/nautilos",
  );
  process.exit(1);
}

const pkg = `@waddie/nautilos-${os}-${arch}`;
let bin;
try {
  // The platform package ships the binary at its root under this name.
  bin = require.resolve(`${pkg}/nautilos-${os}-${arch}`);
} catch (e) {
  console.error(
    `nautilos: the ${pkg} package is not installed.\n` +
      "It is an optional dependency selected by your OS/arch. If it was skipped, " +
      "reinstall without --no-optional (e.g. npm install -g @waddie/nautilos).",
  );
  process.exit(1);
}

// exec by absolute path so the binary's daemon self-re-exec (argv[0]) works.
const result = spawnSync(bin, process.argv.slice(2), { stdio: "inherit" });

if (result.error) {
  console.error(`nautilos: failed to run ${bin}: ${result.error.message}`);
  process.exit(1);
}
if (result.signal) {
  process.kill(process.pid, result.signal);
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
