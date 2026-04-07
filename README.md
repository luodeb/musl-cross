# musl-cross

Prebuilt musl-based cross-compilation toolchains for Linux targets, powered by [musl-cross-make](https://github.com/richfelker/musl-cross-make).

## Supported Targets

| Target | Description |
|--------|-------------|
| `x86_64-linux-musl` | x86_64 (amd64) |
| `aarch64-linux-musl` | ARM 64-bit |
| `riscv64-linux-musl` | RISC-V 64-bit |
| `loongarch64-linux-musl` | LoongArch 64-bit |

## Supported Hosts

| Host | Runner |
|------|--------|
| `linux-x86_64` | Ubuntu 24.04 |
| `linux-aarch64` | Ubuntu 24.04 ARM |
| `darwin-aarch64` | macOS 14 (Apple Silicon) |

## Toolchain Contents

- **GCC** 15.2.0
- **binutils** 2.44
- **musl** 1.2.5

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/luodeb/musl-cross/main/install.sh | bash
```

The installer runs in interactive mode and will guide you through:

1. **Target selection** — choose the target architecture (x86_64, aarch64, riscv64, loongarch64)
2. **Install location** — defaults to `~/.musl-cross`, customizable

It automatically fetches the latest release from GitHub.

After installation, add the toolchain to your `PATH`:

```bash
export PATH="$HOME/.musl-cross/bin:$PATH"
```

### Non-interactive Install

You can also set environment variables for automated installation:

```bash
export MUSL_CROSS_TARGET=aarch64       # Target architecture
export MUSL_CROSS_DIR="$HOME/.musl-cross"  # Install directory
export MUSL_CROSS_TAG="v1.0.2"        # Release tag, or "latest"
bash install.sh
```

## Manual Install

Download the archive for your host and target from [Releases](https://github.com/luodeb/musl-cross/releases).

Asset naming pattern:

```
{host_os}-{host_arch}-host-{target_arch}-linux-musl-gcc.tar.gz
```

For example, on an Apple Silicon Mac targeting aarch64:

```bash
curl -fSL -o musl-cross.tar.gz \
  https://github.com/luodeb/musl-cross/releases/latest/download/darwin-aarch64-host-aarch64-linux-musl-gcc.tar.gz
mkdir -p ~/.musl-cross
tar -xzf musl-cross.tar.gz -C ~/.musl-cross
export PATH="$HOME/.musl-cross/bin:$PATH"
```

## Usage

### Compile a C program

```bash
aarch64-linux-musl-gcc -o hello hello.c
```

### Static linking (default with musl)

```bash
aarch64-linux-musl-gcc -static -o hello hello.c
```

### Using sysroot explicitly

```bash
aarch64-linux-musl-gcc --sysroot=$HOME/.musl-cross/aarch64-linux-musl/sysroot -o hello hello.c
```

### Available compilers per target

Each target provides the full GCC toolchain:

- `{tuple}-gcc` — C compiler
- `{tuple}-g++` — C++ compiler
- `{tuple}-ld` — Linker
- `{tuple}-as` — Assembler
- `{tuple}-objdump` — Disassembler
- `{tuple}-strip` — Symbol stripper
- `{tuple}-nm` — Symbol lister
- `{tuple}-readelf` — ELF inspector

Where `{tuple}` is one of: `x86_64-linux-musl`, `aarch64-linux-musl`, `riscv64-linux-musl`, `loongarch64-linux-musl`.

## Building from Source

This repo uses GitHub Actions to build all toolchains. To trigger a build:

1. Push a tag (`v1.0.0`, etc.) — this automatically builds and publishes a release
2. Or use `workflow_dispatch` with a `release_tag` input

The workflow produces 12 assets (3 hosts × 4 targets) and publishes them to a GitHub Release.

## License

Toolchain components are licensed under their respective licenses (GPL for GCC/binutils, MIT for musl). Build scripts in this repository are provided as-is.
