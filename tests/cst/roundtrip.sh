#!/usr/bin/env bash
# Every .zs file under tests/, lib/ and examples/ parses into a syntax tree whose tokens and trivia
# give back its text byte for byte (0019's lossless tree); prints the count checked.
cd "$(dirname "$0")/../.."
files=$(find tests lib examples -name '*.zs' | sort)
bin/zs tree --check $files 2>&1 | grep 'tree.s text differs' && exit 1
echo "$(echo "$files" | wc -l) files"
