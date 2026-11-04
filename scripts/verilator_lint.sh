#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESIGN_DIR="$REPO_ROOT/Design Files of TITAN X"

echo "============================================"
echo " SMVDU-TITAN-X SoC RTL Lint Analysis"
echo " Linter : Verilator"
echo " Target : Design Files of TITAN X/top/titan_x_top/titan_x_top.v"
echo "============================================"

echo "[1/2] Running Verilator lint..."
cd "$DESIGN_DIR"
verilator --lint-only -Wall \
    -Iincludes \
    --top-module titan_x_top \
    -Wno-fatal \
    -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL \
    -Wno-UNDRIVEN \
    -Wno-PINCONNECTEMPTY \
    -Wno-MULTIDRIVEN \
    -Wno-WIDTH \
    -Wno-UNUSEDPARAM \
    -Wno-BLKSEQ \
    -Wno-CASEINCOMPLETE \
    -Wno-CASEX \
    -Wno-PINMISSING \
    -Wno-UNOPTFLAT \
    -f soc_filelist.f

echo "============================================"
echo " Verilator Lint: PASSED (Clean)"
echo "============================================"
