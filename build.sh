#!/bin/bash
# Build the agentdesk native tools. Requires the Xcode command line tools.
set -e; cd "$(dirname "$0")"; mkdir -p bin
CORE="oracle axact agentdesk-daemon hidden-display"
EXP="experiments/routing-lab experiments/activation-lab experiments/activator experiments/foreign-winop experiments/alphacheck experiments/holdwin"
for f in $CORE $EXP; do
  clang -Wno-deprecated-declarations -fobjc-arc -fmodules -framework AppKit -framework ApplicationServices "src/$f.m" -o "bin/$(basename $f)" && echo "built $(basename $f)"
done
echo "done. tools are in ./bin ; run ./cli/agentdesk up"
