#!/usr/bin/env bash
# Build a signed, static APT repository from component .deb files. Hosting is
# deliberately separate; the release workflow publishes this tree to Pages.

set -euo pipefail

INPUT_DIR=""
OUTPUT_DIR=""
SUITE=trixie
SIGNING_KEY="${APT_SIGNING_KEY_FINGERPRINT:-}"

usage() {
    cat <<USAGE
Usage: scripts/build-apt-repository.sh --input DIR --output DIR [options]

Options:
  --suite NAME        APT suite (default: trixie)
  --signing-key FPR   GPG signing key fingerprint (or set
                      APT_SIGNING_KEY_FINGERPRINT)
  -h, --help          Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) INPUT_DIR="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --suite) SUITE="$2"; shift 2 ;;
        --signing-key) SIGNING_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -d "$INPUT_DIR" && -n "$OUTPUT_DIR" && -n "$SIGNING_KEY" ]] || {
    usage >&2
    exit 2
}
[[ ! -e "$OUTPUT_DIR" ]] || {
    echo "output already exists: $OUTPUT_DIR" >&2
    exit 2
}
for command in apt-ftparchive dpkg-scanpackages gpg gzip; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "missing required command: $command" >&2
        exit 2
    }
done

shopt -s nullglob
packages=("$INPUT_DIR"/*.deb)
shopt -u nullglob
[[ ${#packages[@]} -gt 0 ]] || { echo "no .deb files in $INPUT_DIR" >&2; exit 2; }

install -d "$OUTPUT_DIR/pool/main/s/smbproxy-session-vfs"
architectures=()
for package in "${packages[@]}"; do
    arch=$(dpkg-deb -f "$package" Architecture)
    [[ " ${architectures[*]} " == *" $arch "* ]] || architectures+=("$arch")
    install -m 0644 "$package" \
        "$OUTPUT_DIR/pool/main/s/smbproxy-session-vfs/$(basename "$package")"
done

for arch in "${architectures[@]}"; do
    binary_dir="$OUTPUT_DIR/dists/$SUITE/main/binary-$arch"
    install -d "$binary_dir"
    (
        cd "$OUTPUT_DIR"
        dpkg-scanpackages -a "$arch" pool/main > \
            "dists/$SUITE/main/binary-$arch/Packages"
    )
    gzip -n -9 -c "$binary_dir/Packages" > "$binary_dir/Packages.gz"
done

(
    cd "$OUTPUT_DIR"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin='Naimor SMB Proxy' \
        -o APT::FTPArchive::Release::Label='SMB Proxy Session VFS' \
        -o APT::FTPArchive::Release::Suite="$SUITE" \
        -o APT::FTPArchive::Release::Codename="$SUITE" \
        -o APT::FTPArchive::Release::Architectures="${architectures[*]}" \
        -o APT::FTPArchive::Release::Components=main \
        release "dists/$SUITE" > "dists/$SUITE/Release"
)

gpg --batch --yes --local-user "$SIGNING_KEY" --clearsign \
    --output "$OUTPUT_DIR/dists/$SUITE/InRelease" \
    "$OUTPUT_DIR/dists/$SUITE/Release"
gpg --batch --yes --local-user "$SIGNING_KEY" --armor --detach-sign \
    --output "$OUTPUT_DIR/dists/$SUITE/Release.gpg" \
    "$OUTPUT_DIR/dists/$SUITE/Release"
gpg --batch --yes --export "$SIGNING_KEY" \
    > "$OUTPUT_DIR/smbproxy-session-vfs-archive-keyring.gpg"

echo "$OUTPUT_DIR"
