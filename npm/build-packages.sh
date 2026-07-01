#!/usr/bin/env sh
# Materialise the publishable npm packages from prebuilt binaries.
#
#   npm/build-packages.sh <version> <artifacts-dir> <out-dir>
#
# <version>        semver without a leading v, e.g. 0.2.0
# <artifacts-dir>  holds the release binaries named nautilos-<os>-<arch>
# <out-dir>        emptied and filled with one directory per package:
#                    <out>/nautilos                 -> @waddie/nautilos (meta)
#                    <out>/nautilos-<os>-<arch>     -> platform packages (x4)
#
# Publish the platform packages first, then the meta package, so the meta's
# optionalDependencies resolve.
set -eu

[ $# -eq 3 ] || { echo "usage: build-packages.sh <version> <artifacts-dir> <out-dir>" >&2; exit 1; }
version="$1"
artifacts="$2"
out="$3"
here=$(cd "$(dirname "$0")" && pwd)
targets="darwin-arm64 darwin-x64 linux-x64 linux-arm64"

command -v node >/dev/null 2>&1 || { echo "build-packages.sh: needs node" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out"

# --- meta package: copy the launcher, stamp the version onto template ---------
mkdir -p "$out/nautilos/bin"
cp "$here/nautilos/bin/nautilos.js" "$out/nautilos/bin/nautilos.js"
cp "$here/nautilos/README.md" "$out/nautilos/README.md"
cp "$here/../LICENSE" "$out/nautilos/LICENSE"
node -e '
  const fs = require("fs");
  const [tpl, ver] = process.argv.slice(1);
  const p = JSON.parse(fs.readFileSync(tpl, "utf8"));
  p.version = ver;
  for (const k of Object.keys(p.optionalDependencies || {})) p.optionalDependencies[k] = ver;
  process.stdout.write(JSON.stringify(p, null, 2) + "\n");
' "$here/nautilos/package.json" "$version" > "$out/nautilos/package.json"

# --- platform packages: one binary each, gated by os/cpu ---------------------
for t in $targets; do
  os=${t%-*}
  arch=${t#*-}
  src="$artifacts/nautilos-$t"
  [ -f "$src" ] || { echo "build-packages.sh: missing binary $src" >&2; exit 1; }
  dir="$out/nautilos-$t"
  mkdir -p "$dir"
  cp "$src" "$dir/nautilos-$t"
  chmod +x "$dir/nautilos-$t"
  cp "$here/../LICENSE" "$dir/LICENSE"
  printf '# @waddie/nautilos-%s\n\nPrebuilt `nautilos` binary for `%s`. Installed automatically as an optional\ndependency of `@waddie/nautilos` for matching hosts. Do not install directly.\n' \
    "$t" "$t" > "$dir/README.md"
  node -e '
    const [ver, os, arch, t] = process.argv.slice(1);
    const p = {
      name: `@waddie/nautilos-${t}`,
      version: ver,
      description: `Nautilos prebuilt binary for ${t}.`,
      homepage: "https://github.com/waddie/nautilos",
      repository: { type: "git", url: "git+https://github.com/waddie/nautilos.git" },
      license: "MIT",
      author: "Tom Waddington",
      os: [os],
      cpu: [arch],
      files: [`nautilos-${t}`],
      preferUnplugged: true
    };
    process.stdout.write(JSON.stringify(p, null, 2) + "\n");
  ' "$version" "$os" "$arch" "$t" > "$dir/package.json"
done

echo "built packages in $out:"
ls -1 "$out"
