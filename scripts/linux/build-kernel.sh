#!/usr/bin/env bash
# Configure and build the X04G kernel, DTB and modules; collect artifacts.
#
# Usage: scripts/linux/build-kernel.sh [kernel-src] [out-dir]
# Env:   JOBS (default nproc), CROSS_COMPILE (default aarch64-linux-gnu-)
#        CONFIG_FRAGMENT (default configs/x04g.config)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../kernel/source.env
source "$ROOT/kernel/source.env"
SRC="${1:-$ROOT/build/linux}"
OUT="${2:-$ROOT/build/out}"
ART="$ROOT/build/artifacts"
JOBS="${JOBS:-$(nproc)}"
FRAG="${CONFIG_FRAGMENT:-$ROOT/configs/x04g.config}"
export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
# CROSS_COMPILE may be "ccache aarch64-linux-gnu-"; strip the wrapper for metadata
TC_PREFIX="${CROSS_COMPILE##* }"
# Empty LOCALVERSION stops setlocalversion from appending "+" (release = 7.3.0-x04g)
export LOCALVERSION=""
export KBUILD_BUILD_USER="x04g"
export KBUILD_BUILD_HOST="x04g-linux"
# Reproducibility: fixed timestamp derived from the kernel commit
export KBUILD_BUILD_TIMESTAMP="$(git -C "$SRC" log -1 --format=%cd --date=rfc2822)"
export SOURCE_DATE_EPOCH="$(git -C "$SRC" log -1 --format=%ct)"

mkdir -p "$OUT" "$ART"
LOG="$ART/build.log"
: > "$LOG"
run() { echo "+ $*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG"; }

cd "$SRC"
run make O="$OUT" defconfig
run scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$FRAG"
run make O="$OUT" olddefconfig

# Report fragment options that did not survive (missing deps / renamed symbols)
echo "== config fragment check ==" | tee -a "$LOG"
MISSING=0
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    sym="${line%%=*}"; want="${line#*=}"
    have="$(grep -E "^${sym}=" "$OUT/.config" | cut -d= -f2- || true)"
    if [ "$want" = "n" ]; then
        [ -z "$have" ] || { echo "WARN: $sym wanted n, got $have" | tee -a "$LOG"; MISSING=1; }
    elif [ "$have" != "$want" ]; then
        echo "WARN: $sym wanted $want, got ${have:-unset}" | tee -a "$LOG"; MISSING=1
    fi
done < "$FRAG"
[ "$MISSING" = 0 ] && echo "all fragment options applied" | tee -a "$LOG"

run make O="$OUT" -j"$JOBS" Image.gz modules dtbs

# ---- Collect artifacts -----------------------------------------------------
KREL="$(cat "$OUT/include/config/kernel.release")"
rm -rf "$ART/boot" "$ART/modules" "$ART"/modules-*.tar.gz
mkdir -p "$ART/boot" "$ART/modules"
cp "$OUT/arch/arm64/boot/Image.gz" "$ART/boot/"
cp "$OUT/arch/arm64/boot/dts/$KERNEL_DTB" "$ART/boot/"
DTB_NAME="$(basename "$KERNEL_DTB")"
# Image.gz with appended DTB: the format Android-style MTK LK usually expects
cat "$ART/boot/Image.gz" "$ART/boot/$DTB_NAME" > "$ART/boot/Image.gz-dtb"
cp "$OUT/.config" "$ART/boot/config-$KREL"
cp "$OUT/System.map" "$ART/boot/System.map-$KREL"
run make -s O="$OUT" INSTALL_MOD_PATH="$ART/modules" INSTALL_MOD_STRIP=1 modules_install
rm -f "$ART/modules/lib/modules/$KREL/build" "$ART/modules/lib/modules/$KREL/source"
tar -C "$ART/modules" -czf "$ART/modules-$KREL.tar.gz" lib
rm -rf "$ART/modules"

# Decompiled DTS for human review
dtc -q -I dtb -O dts -o "$ART/boot/${DTB_NAME%.dtb}.dts" "$ART/boot/$DTB_NAME" || true

# ---- Verify outputs ----------------------------------------------------------
fail() { echo "VERIFY FAILED: $*" | tee -a "$LOG"; exit 1; }
[ -s "$ART/boot/Image.gz" ] || fail "Image.gz missing"
gzip -t "$ART/boot/Image.gz" || fail "Image.gz corrupt"
# arm64 Image header magic "ARM\x64" at offset 0x38
# (decompress fully into a temp file: piping into head would SIGPIPE gzip and trip pipefail)
TMPIMG="$(mktemp)"; gzip -dc "$ART/boot/Image.gz" > "$TMPIMG"
MAGIC="$(od -An -tx1 -j56 -N4 "$TMPIMG" | tr -d ' \n')"; rm -f "$TMPIMG"
[ "$MAGIC" = "41524d64" ] || fail "bad arm64 Image magic ($MAGIC)"
[ "$(od -An -tx1 -N4 "$ART/boot/$DTB_NAME" | tr -d ' \n')" = "d00dfeed" ] || fail "bad DTB magic"
fdtget "$ART/boot/$DTB_NAME" / compatible | grep -q "xiaomi,x04g" || fail "DTB compatible is not xiaomi,x04g"

cat > "$ART/build-info.txt" <<EOF
kernel_release=$KREL
kernel_repo=$KERNEL_REPO
kernel_branch=$KERNEL_BRANCH
kernel_commit=$(git -C "$SRC" rev-parse HEAD)
project_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
config_fragment=$(basename "$FRAG")
patches=$(ls "$ROOT"/patches/kernel/*.patch 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')
toolchain=$(${TC_PREFIX}gcc --version | head -1)
binutils=$(${TC_PREFIX}ld --version | head -1)
build_host=$(uname -srm)
build_date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
(cd "$ART" && find boot -type f -exec sha256sum {} + > SHA256SUMS && sha256sum modules-*.tar.gz >> SHA256SUMS)
echo "== build OK: $KREL ==" | tee -a "$LOG"
cat "$ART/build-info.txt"
ls -la "$ART" "$ART/boot"
