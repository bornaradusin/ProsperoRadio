#!/usr/bin/env bash
# ProsperoRadio - Pinned ps5-opengl SDK build from source.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The prebuilt ps5-opengl release this build used to download went away with
# the original repository. This builds the SDK from the maintained fork at a
# pinned commit into .deps/ps5-opengl-source and prints the SDK prefix (the
# directory holding manifest.sha256). A finished build is reused.
#
# MESA_ARCHIVE names a local copy of the Mesa release tarball the fork pins
# (third_party/mesa-<version>.tar.xz), for hosts that cannot reach
# archive.mesa3d.org. Its SHA-256 is still checked against the pin.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
commit=ec06d8c2da0359e274e409046f0a9586965e4010
url=https://github.com/mihawk-99/ps5-opengl.git

source="$root/.deps/ps5-opengl-source"
prefix="$source/build/sdk/ps5-opengl-gl46"
stamp="$source/build/.sdk-commit"
sdk="$root/.deps/native/ps5-payload-sdk"

verify() {
    (cd "$prefix" && sha256sum --check --strict --quiet manifest.sha256) || {
        echo "ps5-opengl SDK manifest verification failed: $prefix" >&2
        exit 2
    }
}

if [[ -f $prefix/manifest.sha256 && -f $stamp && $(<"$stamp") == "$commit" ]]; then
    verify
    printf '%s\n' "$prefix"
    exit 0
fi

missing=()
for command in git make python3 clang-18 cmake ninja meson bison flex glslangValidator; do
    command -v "$command" >/dev/null || missing+=("$command")
done
if ((${#missing[@]})); then
    echo "building the ps5-opengl SDK needs: ${missing[*]} (see docs/GETTING_STARTED.md)" >&2
    exit 2
fi
# The SDK's host compiler checks link with -fsanitize=undefined.
ubsan="$(clang-18 --print-resource-dir)/lib/linux/libclang_rt.ubsan_standalone-x86_64.a"
[[ -f $ubsan ]] || {
    echo "building the ps5-opengl SDK needs clang's UBSan runtime (libclang-rt-18-dev): $ubsan" >&2
    exit 2
}

# The fork's latest commits changed sources that its GLSL test fixtures record
# without refreshing the fixtures' receipt, so its own self-test rejects them.
# Those fixtures feed only that test, not the installed SDK: record the current
# hashes of exactly the entries that differ, as the project's CI meant to.
refresh_fixture_receipt() {
    python3 -I - "$source/tests/ps5/compute_glsl_fixtures.h" "$source" <<'PY'
import hashlib, json, sys
from pathlib import Path

header, root = Path(sys.argv[1]), Path(sys.argv[2])
begin, end = "/* PS5_GLSL_RECEIPT_BEGIN\n", "\nPS5_GLSL_RECEIPT_END */"
text = header.read_text()
receipt = text.split(begin, 1)[1].split(end, 1)[0]
updated = receipt
for name, recorded in json.loads(receipt)["source_sha256"].items():
    actual = hashlib.sha256((root / name).read_text().encode()).hexdigest()
    if actual != recorded:
        entry = f'"{name}": "{recorded}"'
        assert updated.count(entry) == 1, entry
        updated = updated.replace(entry, f'"{name}": "{actual}"')
        print(f"==> [opengl] Refreshed the fixture receipt hash of {name}")
if updated != receipt:
    old = hashlib.sha256(receipt.encode()).hexdigest()
    new = hashlib.sha256(updated.encode()).hexdigest()
    define = '#define PS5_GLSL_RECEIPT_SHA256 "{}"'
    assert text.count(define.format(old)) == 1
    text = text.replace(begin + receipt + end, begin + updated + end, 1)
    header.write_text(text.replace(define.format(old), define.format(new)))
PY
    # The fork now aligns small colour targets to color_alignment rather than
    # 2 MiB (see the comment above that code in ps5_screen.c), but its
    # source-text audit still looks for the old expression.
    local audit="$source/tests/ps5/verify_gl33_capability_audit.py"
    local screen="$source/src/gallium/ps5/ps5_screen.c"
    local old='tiled_size + PS5_RENDER_ALIGNMENT - 1u' new='tiled_size + color_alignment - 1u'
    if grep -Fq "\"$old\" in SCREEN" "$audit" && ! grep -Fq "$old" "$screen" &&
        grep -Fq "$new" "$screen"; then
        sed -i "s/\"$old\" in SCREEN/\"$new\" in SCREEN/" "$audit"
        echo "==> [opengl] Refreshed the colour-allocation audit for the fork's small-texture alignment"
    fi
}

bash "$root/tools/setup-native-dependencies.sh" >/dev/null
[[ -x $sdk/bin/prospero-clang ]] || {
    echo "the PS5 payload SDK compiler is missing: $sdk/bin/prospero-clang" >&2
    exit 2
}

if [[ $(git -C "$source" rev-parse HEAD 2>/dev/null || true) != "$commit" ]]; then
    printf '==> [opengl] Fetching ps5-opengl %s\n' "${commit:0:7}" >&2
    rm -rf -- "$source"
    git init --quiet "$source"
    git -C "$source" remote add origin "$url"
    git -C "$source" fetch --quiet --depth 1 origin "$commit"
    git -C "$source" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
fi
[[ $(git -C "$source" rev-parse HEAD) == "$commit" ]] || {
    echo "ps5-opengl checkout is not the pinned commit" >&2
    exit 2
}

mesa_version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["mesa"]["version"])' \
    "$source/dependencies.json")
if [[ -n ${MESA_ARCHIVE:-} ]]; then
    mkdir -p "$source/third_party"
    cp -- "$(realpath -e -- "$MESA_ARCHIVE")" "$source/third_party/mesa-$mesa_version.tar.xz"
fi

mkdir -p "$source/build"
log="$source/build/opengl-build.log"
printf '==> [opengl] Building the ps5-opengl SDK from source (log: %s)\n' "$log" >&2
rm -f -- "$stamp"
if ! { make -C "$source" source-fetch && refresh_fixture_receipt &&
    make -C "$source" sdk PS5_PAYLOAD_SDK="$sdk"; } >"$log" 2>&1; then
    grep -nEi 'error:|No such file|ModuleNotFound|FAILED|urlopen error' "$log" | tail -n 25 >&2 || true
    tail -n 30 "$log" >&2
    if [[ ! -f $source/third_party/mesa-$mesa_version.tar.xz ]]; then
        printf 'Mesa %s could not be downloaded. Fetch %s yourself and rerun with\n' \
            "$mesa_version" "https://archive.mesa3d.org/mesa-$mesa_version.tar.xz" >&2
        printf '  MESA_ARCHIVE=/path/to/mesa-%s.tar.xz make\n' "$mesa_version" >&2
    fi
    echo "ps5-opengl SDK build failed; full log: $log" >&2
    exit 2
fi
grep -F '==> [opengl] Refreshed' "$log" >&2 || true
for required in manifest.sha256 lib/libPS5OpenGL.a; do
    [[ -f $prefix/$required ]] || { echo "ps5-opengl SDK build left no $required" >&2; exit 2; }
done
verify
printf '%s\n' "$commit" >"$stamp"
printf '%s\n' "$prefix"
