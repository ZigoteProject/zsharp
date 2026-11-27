#!/usr/bin/env bash
# Checks the proofs with Rocq (rocq compile), in a temporary directory so nothing is left here.
# Prints each theorem's assumptions: "Closed under the global context" is none.
set -eu
cd "$(dirname "$0")"
command -v rocq > /dev/null || { echo "no rocq"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cp ./*.v "$t" && cd "$t"
# in the order they build on each other
for f in Ownership Tokens Calls; do
  if [ -f $f.v ]; then rocq compile -Q . Proofs $f.v 2>&1; fi
done
