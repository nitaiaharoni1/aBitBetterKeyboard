#!/bin/bash
# The grouped-key sweep. Self-tests first, then measures.
#
# No simulator, no Swift, no network. Seconds, not minutes — which is what makes
# sweeping the dial affordable at all.
set -euo pipefail
cd "$(dirname "$0")"

# Missing-data checks live in run.require_data, which selftest.py and run.py both
# call, so there is one list of required files rather than a copy in shell.
python3 selftest.py
exec python3 run.py "$@"
