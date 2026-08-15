#!/bin/bash
# The glide-typing spike (NIT-17): self-test, then the sweep.
#
#   Bar/glide/harness/run.sh
#
# No simulator, no Swift, no network — a Python sweep over synthesised swipe
# paths, mirroring how Bar/grouped/harness/run.sh is built. Needs
# Bar/grouped/data/{rows,testtext,lexicon-en,lexicon-he}.json, which
# Bar/grouped/README.md explains how to regenerate if missing.
set -euo pipefail
cd "$(dirname "$0")"
python3 selftest.py
exec python3 run.py
