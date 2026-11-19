#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
open -n "$PWD/build/BurndownBar.app" --args --replace-running
