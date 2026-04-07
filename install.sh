#!/usr/bin/env bash
set -euo pipefail

REPO="luodeb/musl-cross"
API_BASE="https://api.github.com/repos/${REPO}"

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }

# ── Detect host platform ────────────────────────────────────────────────
detect_host() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux)  host_os="linux" ;;
        darwin) host_os="darwin" ;;
        *)      err "Unsupported OS: $os"; exit 1 ;;
    esac

    case "$arch" in
        x86_64|amd64)   host_arch="x86_64" ;;
        aarch64|arm64)  host_arch="aarch64" ;;
        *)              err "Unsupported architecture: $arch"; exit 1 ;;
    esac

    host_id="${host_os}-${host_arch}"
}

# ── Get latest release tag ──────────────────────────────────────────────
get_latest_tag() {
    info "Fetching latest release information..."
    latest_tag=$(curl -fsSL "${API_BASE}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | head -1 \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        err "Failed to get latest release tag. Check network or repo."
        exit 1
    fi
    ok "Latest release: ${latest_tag}"
}

# ── List available releases ─────────────────────────────────────────────
list_releases() {
    info "Fetching available releases..."
    curl -fsSL "${API_BASE}/releases" 2>/dev/null \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
        | head -20
}

# ── Non-interactive mode ─────────────────────────────────────────────────
non_interactive=false

check_non_interactive() {
    if [ -n "${MUSL_CROSS_TARGET:-}" ]; then
        non_interactive=true
        target_arch="${MUSL_CROSS_TARGET}"
        case "$target_arch" in
            x86_64)      target_tuple="x86_64-linux-musl" ;;
            aarch64)     target_tuple="aarch64-linux-musl" ;;
            riscv64)     target_tuple="riscv64-linux-musl" ;;
            loongarch64) target_tuple="loongarch64-linux-musl" ;;
            *)           err "Unknown target: $target_arch"; exit 1 ;;
        esac
        ok "Target (non-interactive): ${target_tuple}"
    fi

    if [ -n "${MUSL_CROSS_DIR:-}" ]; then
        non_interactive=true
        install_dir="${MUSL_CROSS_DIR/#\~/$HOME}"
        ok "Install dir (non-interactive): ${install_dir}"
    fi

    if [ -n "${MUSL_CROSS_TAG:-}" ]; then
        non_interactive=true
        if [ "$MUSL_CROSS_TAG" = "latest" ]; then
            get_latest_tag
        else
            latest_tag="$MUSL_CROSS_TAG"
            ok "Release (non-interactive): ${latest_tag}"
        fi
    fi
}

# ── Interactive target selection ─────────────────────────────────────────
select_target() {
    echo ""
    printf "${BOLD}Available target architectures:${RESET}\n"
    echo "  1) x86_64       (x86_64-linux-musl)"
    echo "  2) aarch64      (aarch64-linux-musl)"
    echo "  3) riscv64      (riscv64-linux-musl)"
    echo "  4) loongarch64  (loongarch64-linux-musl)"
    echo ""

    default_target=1
    printf "Select target [1-4] (default: ${default_target}): "
    read -r choice
    choice="${choice:-$default_target}"

    case "$choice" in
        1) target_arch="x86_64";      target_tuple="x86_64-linux-musl" ;;
        2) target_arch="aarch64";     target_tuple="aarch64-linux-musl" ;;
        3) target_arch="riscv64";     target_tuple="riscv64-linux-musl" ;;
        4) target_arch="loongarch64"; target_tuple="loongarch64-linux-musl" ;;
        *) err "Invalid choice: $choice"; exit 1 ;;
    esac
    ok "Target: ${target_tuple}"
}

# ── Interactive install path ────────────────────────────────────────────
select_install_dir() {
    local default_dir
    default_dir="$HOME/.musl-cross"

    echo ""
    printf "Install directory (default: ${default_dir}): "
    read -r user_dir
    install_dir="${user_dir:-$default_dir}"

    # Expand ~
    install_dir="${install_dir/#\~/$HOME}"

    ok "Install directory: ${install_dir}"
}

# ── Interactive release selection ────────────────────────────────────────
select_release() {
    local tags
    tags="$(list_releases)"

    if [ -z "$tags" ]; then
        err "No releases found."
        exit 1
    fi

    echo ""
    printf "${BOLD}Available releases:${RESET}\n"
    local i=1
    local tag_array=()
    while IFS= read -r tag; do
        printf "  %2d) %s\n" "$i" "$tag"
        tag_array+=("$tag")
        i=$((i + 1))
    done <<< "$tags"

    local default_choice=1
    echo ""
    printf "Select release [1-$((i-1))] (default: ${default_choice}): "
    read -r choice
    choice="${choice:-$default_choice}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$((i-1))" ]; then
        err "Invalid choice: $choice"
        exit 1
    fi

    latest_tag="${tag_array[$((choice-1))]}"
    ok "Selected release: ${latest_tag}"
}

# ── Build asset name ────────────────────────────────────────────────────
build_asset_name() {
    asset_name="${host_os}-${host_arch}-host-${target_arch}-linux-musl-gcc"
    asset_file="${asset_name}.tar.gz"
    asset_sha256="${asset_file}.sha256"
}

# ── Download ────────────────────────────────────────────────────────────
download() {
    local download_url="https://github.com/${REPO}/releases/download/${latest_tag}/${asset_file}"
    local sha256_url="https://github.com/${REPO}/releases/download/${latest_tag}/${asset_sha256}"

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    info "Downloading ${asset_file}..."
    if ! curl -fSL --progress-bar -o "${tmp_dir}/${asset_file}" "$download_url"; then
        err "Download failed. Asset '${asset_file}' may not exist for host '${host_id}'."
        err "URL: ${download_url}"
        exit 1
    fi
    ok "Download complete."

    # Verify SHA256
    info "Verifying SHA256 checksum..."
    if curl -fsSL -o "${tmp_dir}/${asset_sha256}" "$sha256_url" 2>/dev/null; then
        local expected actual
        expected="$(awk '{print $1}' "${tmp_dir}/${asset_sha256}")"
        if command -v sha256sum >/dev/null 2>&1; then
            actual="$(sha256sum "${tmp_dir}/${asset_file}" | awk '{print $1}')"
        elif command -v shasum >/dev/null 2>&1; then
            actual="$(shasum -a 256 "${tmp_dir}/${asset_file}" | awk '{print $1}')"
        else
            warn "No sha256sum/shasum found, skipping verification."
            actual="$expected"
        fi

        if [ "$expected" != "$actual" ]; then
            err "SHA256 mismatch!"
            err "  Expected: ${expected}"
            err "  Actual:   ${actual}"
            exit 1
        fi
        ok "SHA256 verified."
    else
        warn "SHA256 file not found, skipping verification."
    fi
}

# ── Extract ─────────────────────────────────────────────────────────────
extract() {
    info "Extracting to ${install_dir}..."
    mkdir -p "$install_dir"
    tar -xzf "${tmp_dir}/${asset_file}" -C "$install_dir"
    ok "Extraction complete."
}

# ── Post-install setup ──────────────────────────────────────────────────
post_install() {
    local toolchain_dir="${install_dir}/output"
    local bin_dir="${toolchain_dir}/bin"
    local sysroot="${toolchain_dir}/${target_tuple}/sysroot"

    echo ""
    printf "${BOLD}${GREEN}Installation complete!${RESET}\n"
    echo ""

    # Verify compiler
    local gcc="${bin_dir}/${target_tuple}-gcc"
    if [ -x "$gcc" ]; then
        ok "Compiler found: ${gcc}"
        info "$(${gcc} --version | head -1)"
    else
        warn "Compiler not found at: ${gcc}"
    fi

    echo ""
    printf "${BOLD}Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):${RESET}\n"
    echo ""
    printf "  ${CYAN}export PATH=\"${bin_dir}:\$PATH\"${RESET}\n"
    echo ""

    if [ -d "$sysroot" ]; then
        echo "Sysroot location:"
        printf "  ${CYAN}${sysroot}${RESET}\n"
        echo ""
        echo "Compile example:"
        printf "  ${CYAN}${target_tuple}-gcc --sysroot=${sysroot} -o hello hello.c${RESET}\n"
    else
        echo "Compile example:"
        printf "  ${CYAN}${target_tuple}-gcc -o hello hello.c${RESET}\n"
    fi

    echo ""
    printf "${BOLD}Quick test:${RESET}\n"
    printf "  ${CYAN}${bin_dir}/${target_tuple}-gcc -v${RESET}\n"
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────
main() {
    echo ""
    printf "${BOLD}╔══════════════════════════════════════╗╗\n"
    printf "║  musl-cross toolchain installer      ║\n"
    printf "║  ${REPO}    ║\n"
    printf "╚══════════════════════════════════════╝╝${RESET}\n"

    # 1. Detect host
    detect_host
    ok "Host platform: ${host_id}"

    # 2. Check non-interactive mode / select release
    check_non_interactive
    if [ -z "${latest_tag:-}" ]; then
        select_release
    fi

    # 3. Select target
    if [ -z "${target_tuple:-}" ]; then
        select_target
    fi

    # 4. Select install dir
    if [ -z "${install_dir:-}" ]; then
        select_install_dir
    fi

    # 5. Build asset name
    build_asset_name
    info "Asset: ${asset_file}"

    # 6. Download & verify
    download

    # 7. Extract
    extract

    # 8. Post-install info
    post_install
}

main "$@"
