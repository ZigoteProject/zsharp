#!/usr/bin/env bash
# Profile-guided optimization: a build with --profile-generate writes a profile when it runs,
# llvm-profdata merges it, and a build with --profile-use takes it. The profile names a module's
# internal functions after its source file, the same in every build, so the second build finds
# them (named after a temporary file, it once found none, and the program got slower).
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
cp tests/modules/parts.zs tests/modules/trees.zs "$t/" # recursive functions: not inlined away
bin/zs build "$t/parts.zs" --profile-generate -o "$t/gen" && (cd "$t" && LLVM_PROFILE_FILE=run.profraw ./gen >/dev/null)
llvm-profdata merge -o "$t/run.profdata" "$t/run.profraw"
names=$(llvm-profdata show --all-functions "$t/run.profdata" | grep -E '^  [^ ]+:$')
echo "internal functions profiled, by source file: $(echo "$names" | grep -o '^  [a-z]*\.zs;' | sort -u | tr -d ' ;' | paste -sd ' ' -)"
echo "named after a temporary file: $(echo "$names" | grep -c '\.ll;')"
bin/zs build "$t/parts.zs" --profile-use "$t/run.profdata" -o "$t/use" && "$t/use" | diff - tests/modules/parts.out && echo "with the profile: the same output"
