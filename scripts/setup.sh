#!/usr/bin/env bash
#
# scripts/setup.sh — install the Ada toolchain for building beep.
#
# What it does:
#   1. Installs Alire (the Ada package manager) into ~/.local/bin if missing.
#   2. Runs `alr update` to fetch GNAT (compiler) + GNATprove (SPARK prover)
#      into the project, as declared in alire.toml.
#
# Why not Homebrew?
#   Homebrew has no `gnat`, `alire`, or `gnatprove` formula/cask on macOS.
#   AdaCore points to Alire as the package manager for non-industrial use,
#   which is what this repo already uses. Alire ships prebuilt GNAT +
#   GNATprove for macOS arm64, so it is the "brew equivalent" here.
#
# Usage:
#   ./scripts/setup.sh
#
# After setup, ensure ~/.local/bin is on your PATH:
#   export PATH="$HOME/.local/bin:$PATH"
#
set -euo pipefail

ALR_VERSION="${ALR_VERSION:-v2.1.1}"
ALR_BIN="${HOME}/.local/bin/alr"

# --- 1. Install Alire (skip if already present) -----------------------------
if command -v alr >/dev/null 2>&1; then
   echo "alr already installed: $(command -v alr)"
elif [[ -x "${ALR_BIN}" ]]; then
   export PATH="${HOME}/.local/bin:${PATH}"
   echo "alr found at ${ALR_BIN}"
else
   ARCH="$(uname -m)"
   case "${ARCH}" in
      arm64)  ALR_ARCH="aarch64-macos" ;;
      x86_64) ALR_ARCH="x86_64-macos"  ;;
      *) echo "Unsupported arch: ${ARCH} (expected arm64 or x86_64)" >&2; exit 1 ;;
   esac
   VER="${ALR_VERSION#v}"
   URL="https://github.com/alire-project/alire/releases/download/${ALR_VERSION}/alr-${VER}-bin-${ALR_ARCH}.zip"
   echo "Installing Alire ${ALR_VERSION} (${ALR_ARCH}) from: ${URL}"
   WORK="$(mktemp -d)"
   trap 'rm -rf "${WORK}"' EXIT
   curl -sSL -o "${WORK}/alr.zip" "${URL}"
   unzip -o -q "${WORK}/alr.zip" -d "${WORK}/extract"
   mkdir -p "${HOME}/.local/bin"
   install -m 0755 "${WORK}/extract/bin/alr" "${ALR_BIN}"
   export PATH="${HOME}/.local/bin:${PATH}"
   echo "Installed: $(alr --version)"
fi

# --- 2. Fetch GNAT + GNATprove into this project ----------------------------
cd "$(cd "$(dirname "$0")/.." && pwd)"
echo "Running 'alr update' to provision GNAT + GNATprove..."
alr -n update

echo
echo "Setup complete. Toolchain available via 'alr exec':"
# Capture full output to a variable first (no pipe). Piping `gnatprove --version`
# into `head`/`sed -n 1p` triggers SIGPIPE (exit 141): gnatprove emits several
# lines (alt-ergo/cvc5/z3) and the slice tool exits early, which `set -o
# pipefail` then propagates. Slicing the captured string avoids the pipe.
first_line() { local s="$1"; printf '%s' "${s%%$'\n'*}"; }
GNATMAKE_V="$(alr exec -- gnatmake --version 2>&1)"
GPRBUILD_V="$(alr exec -- gprbuild --version 2>&1)"
GNATPROVE_V="$(alr exec -- gnatprove --version 2>&1)"
echo "  $(first_line "${GNATMAKE_V}")"
echo "  $(first_line "${GPRBUILD_V}")"
echo "  $(first_line "${GNATPROVE_V}")"
echo
echo "Build with:  BEEP_OS=darwin alr build"
echo "Run tests:   ./obj/beep_core_tests && ./obj/beep_config_tests"
echo "SPARK proof: ./scripts/prove.sh"
