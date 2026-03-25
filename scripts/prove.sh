#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

alr exec -- gnatprove -P beep.gpr -u beep-core-safety.adb --mode=prove --level=2
