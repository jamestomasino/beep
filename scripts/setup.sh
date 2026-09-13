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

# --- 3. Expose `gnatls` on PATH (idempotent) --------------------------------
# GNAT FSF 16's `gnatls` is the LEGACY unit/dependency-listing utility (NOT the
# LSP). A small wrapper makes it reachable without `alr exec`. Editor LSP is
# AdaCore's separate GNAT Language Server (VS Code "AdaCore.ada" extension or
# GNAT Studio) — see README "Editor / LSP".
GNATLS_BIN="${HOME}/.local/bin/gnatls"
cat > "${GNATLS_BIN}" <<'WRAP'
#!/usr/bin/env bash
# Expose the Alire-provisioned `gnatls` on PATH.
#
# NOTE: in GNAT FSF 16.x, `gnatls` is the LEGACY unit-listing / dependency
# utility (list units, changed/unchanged objects, unit dependencies for .o
# files). It is NOT the GNAT Language Server (LSP). Use it for build/dependency
# inspection, e.g.:
#   gnatls -u obj/main.o          # list units in an object
#   gnatls -a obj/main.o          # units incl. predefined
#   gnatls -v obj/main.o          # verbose (full paths + status)
#
# For editor IntelliSense/LSP, use the AdaCore.ada extension (VS Code) or
# GNAT Studio, which bundle AdaCore's GNAT Language Server.
#
# Version-agnostic: resolves alr from this script's own directory, then
# forwards all args so `alr exec -- gnatls <args>` behaves identically.
HERE="$(cd "$(dirname "$0")" && pwd)"
ALR="${HERE}/alr"
[[ -x "${ALR}" ]] || ALR="$(command -v alr || true)"
exec "${ALR}" exec -- gnatls "$@"
WRAP
chmod 0755 "${GNATLS_BIN}"
echo "  gnatls wrapper: ${GNATLS_BIN}"
echo

# --- 4. Install ada_language_server (LSP server, driven by ALE in Vim) ------
# AdaCore's GNAT Language Server. ALE's built-in `adals` linter launches this
# over stdio (see .lvimrc). Pinned prebuilt release (darwin-arm64 / x86_64).
# Idempotent: skipped if a working binary is already on PATH or at the target.
ALS_VERSION="${ALS_VERSION:-2026.3.202607051}"
ALS_BIN="${HOME}/.local/bin/ada_language_server"
ALS_LIBDIR="${HOME}/.local/lib/als"
if [[ -x "${ALS_BIN}" ]] && "${ALS_BIN}" --version >/dev/null 2>&1; then
   echo "ada_language_server already installed: $(command -v ada_language_server 2>/dev/null || echo "${ALS_BIN}")"
else
   ARCH="$(uname -m)"
   case "${ARCH}" in
      arm64)  ALS_GHA="darwin-arm64" ;;
      x86_64) ALS_GHA="darwin-x64"   ;;
      *) echo "Unsupported arch for ada_language_server: ${ARCH}" >&2; exit 1 ;;
   esac
   ALS_URL="https://github.com/AdaCore/ada_language_server/releases/download/${ALS_VERSION}/als-${ALS_VERSION}-${ALS_GHA}.tar.gz"
   echo "Installing ada_language_server ${ALS_VERSION} (${ALS_GHA})..."
   WORK="$(mktemp -d)"
   als_cleanup() { rm -rf "${WORK}"; }
   trap als_cleanup EXIT
   curl -sSL -o "${WORK}/als.tar.gz" "${ALS_URL}"
   tar xzf "${WORK}/als.tar.gz" -C "${WORK}"
   ALS_SRC="$(find "${WORK}" -type f -name ada_language_server -print -quit)"
   [[ -n "${ALS_SRC}" ]] || { echo "  could not locate ada_language_server in release" >&2; exit 1; }
   SRC_DIR="$(dirname "${ALS_SRC}")"
   mkdir -p "${HOME}/.local/bin" "${ALS_LIBDIR}"
   install -m 0755 "${ALS_SRC}" "${ALS_BIN}"
   # The binary links @rpath/libgmp.10.dylib but the release ships no rpath.
   # Ship the dylib and bake in the rpath so it loads without DYLD_LIBRARY_PATH.
   if [[ -f "${SRC_DIR}/libgmp.10.dylib" ]]; then
      install -m 0644 "${SRC_DIR}/libgmp.10.dylib" "${ALS_LIBDIR}/libgmp.10.dylib"
      if otool -L "${ALS_BIN}" 2>/dev/null | grep -q 'libgmp' \
         && ! otool -D "${ALS_BIN}" 2>/dev/null | grep -q "${ALS_LIBDIR}"; then
         install_name_tool -add_rpath "${ALS_LIBDIR}" "${ALS_BIN}" 2>/dev/null || true
      fi
   fi
   "${ALS_BIN}" --version || { echo "  ada_language_server failed to run after install" >&2; exit 1; }
   trap - EXIT
   rm -rf "${WORK}"
   echo "  ada_language_server: $(command -v ada_language_server 2>/dev/null || echo "${ALS_BIN}")"
fi
echo

echo "Build with:  BEEP_OS=darwin alr build"
echo "Run tests:   ./obj/beep_core_tests && ./obj/beep_config_tests"
echo "SPARK proof: ./scripts/prove.sh"
echo "Editor LSP:  Vim + ALE (see .lvimrc and README 'Editor / LSP')"
