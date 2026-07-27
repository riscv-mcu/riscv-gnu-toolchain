#!/usr/bin/env bash

# Test script for riscv-gnu-toolchain: build gcc/sim/dejagnu once, then run
# both gcc (report-newlib) and binutils (report-binutils) testsuites.
# Mirrors the test_toolchain_report CI job so it can be run locally.
#
# Usage:
#   ./scripts/toolchain/test.sh
#   ./scripts/toolchain/test.sh "rv32gc ilp32d"        # arch abi (space separated)
#   ARCH=rv64gc ABI=lp64d ./scripts/toolchain/test.sh
#
# Environment variables (override on the command line):
#   ARCH        target arch, e.g. rv64gc        (default rv64gc)
#   ABI         target abi,  e.g. lp64d         (default lp64d)
#   SIM         simulator,  e.g. spike/qemu    (default spike)
#   CMODEL      code model, e.g. medlow/medany (default medlow)
#   ISASPEC     isa spec version, e.g. 20191213/2.2 (default 20191213)
#   TUNE        mtune,      e.g. rocket/generic (default rocket)
#   JOBS        parallel jobs for build and test (default nproc)
#   PREFIX      install prefix (default $(pwd)/build-toolchain-out)
#   CLEAN       if non-empty, rm -rf build-* before building (default 1)
#   BUILDONLY   if non-empty, only build (skip tests)

set -e

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)
cd "$SCRIPTDIR/../.." 2>/dev/null || cd "$(dirname "$SCRIPTDIR")"

# --- parse args: first positional "arch abi" overrides ARCH/ABI ---
if [ $# -ge 1 ] && [ -n "$1" ]; then
    ARCH=$(echo "$1" | awk '{print $1}')
    ABI=$(echo "$1" | awk '{print $2}')
fi

ARCH=${ARCH:-rv64gc}
ABI=${ABI:-lp64d}
SIM=${SIM:-spike}
CMODEL=${CMODEL:-medlow}
ISASPEC=${ISASPEC:-20191213}
TUNE=${TUNE:-rocket}
JOBS=${JOBS:-$(nproc)}
PREFIX=${PREFIX:-$(pwd)/build-toolchain-out}
CLEAN=${CLEAN:-1}

echo "INFO: Test toolchain for $ARCH/$ABI (sim=$SIM, cmodel=$CMODEL, isaspec=$ISASPEC, tune=$TUNE, jobs=$JOBS)"

# --- step 0: clean leftover build directories and stamps ---
# stamps/ must also be removed: make skips a step if its stamp exists, even
# if the build dir was deleted, leading to "Nothing to be done" + missing .sum
if [ -n "$CLEAN" ]; then
    echo "INFO: rm -rf build-* stamps (ignore missing)"
    rm -rf build-* stamps
fi

# --- step 1: configure ---
echo "INFO: configure toolchain"
./configure --prefix="$PREFIX" \
    --with-arch="$ARCH" --with-abi="$ABI" \
    --with-sim="$SIM" --with-cmodel="$CMODEL" \
    --with-isa-spec="$ISASPEC" --with-tune="$TUNE"

# ABI is only needed for ./configure --with-abi above. Unset it before make:
# GCC's bundled GMP configure reads the ABI env var (expecting "standard"/"32"/"64")
# and our ABI=ilp32d/lp64d would make it fail with "ABI=ilp32d is not a valid choice".
# Keep the value in RVABI for log filenames below.
RVABI="$ABI"
unset ABI

# Short tag for log filenames: extract rv32/rv64 from ARCH + ABI.
# Using the full $ARCH (which may be a long march string) can exceed the
# filesystem NAME_MAX (255 bytes), so use a short "rvNN-abi" tag instead.
case "$ARCH" in
    rv32*) TAG="rv32-$RVABI" ;;
    rv64*) TAG="rv64-$RVABI" ;;
    *)     TAG="$RVABI" ;;
esac

# --- step 2: build gcc (stage1 + newlib + stage2 + gdb) ---
echo "INFO: build gcc (make newlib -j$JOBS)"
make newlib -j"$JOBS" 2>&1 | tee build-gcc-"$TAG".log
buildgcc=${PIPESTATUS[0]}
if [ $buildgcc -ne 0 ]; then
    echo "ERROR: gcc build failed"
    exit $buildgcc
fi

# --- step 3: build sim (spike + pk for --with-sim=spike) ---
echo "INFO: build sim (make build-sim -j$JOBS)"
make build-sim -j"$JOBS" 2>&1 | tee build-sim-"$TAG".log
buildsim=${PIPESTATUS[0]}
if [ $buildsim -ne 0 ]; then
    echo "ERROR: sim build failed"
    exit $buildsim
fi

# --- step 4: build dejagnu (test framework) ---
echo "INFO: build dejagnu (make stamps/build-dejagnu -j$JOBS)"
make stamps/build-dejagnu -j"$JOBS" 2>&1 | tee build-dejagnu-"$TAG".log
builddejagnu=${PIPESTATUS[0]}
if [ $builddejagnu -ne 0 ]; then
    echo "ERROR: dejagnu build failed"
    exit $builddejagnu
fi

if [ -n "$BUILDONLY" ]; then
    echo "INFO: BUILDONLY set, skipping tests"
    exit 0
fi

# --- step 5: run gcc testsuite ---
echo "INFO: run gcc testsuite (make report-newlib -j$JOBS)"
make report-newlib -j"$JOBS" 2>&1 | tee report-newlib-"$TAG".log
newlibsts=${PIPESTATUS[0]}

# --- step 6: run binutils testsuite ---
echo "INFO: run binutils testsuite (make report-binutils -j$JOBS)"
make report-binutils -j"$JOBS" 2>&1 | tee report-binutils-"$TAG".log
binutilssts=${PIPESTATUS[0]}

# --- print both testsuite-filter summaries together for easy comparison ---
echo ""
echo "============================================================"
echo "             Testsuite Summary for $ARCH/$RVABI"
echo "============================================================"
echo "=== gcc testsuite-filter summary ==="
python3 scripts/testsuite-filter gcc newlib test/allowlist \
    $(find build-gcc-newlib-stage2/gcc/testsuite/ -name "*.sum" | paste -sd "," -) 2>&1 | tail -20 || true
echo ""
echo "=== binutils testsuite-filter summary ==="
python3 scripts/testsuite-filter binutils newlib test/allowlist \
    $(find build-binutils-newlib/ -name "*.sum" | paste -sd "," -) 2>&1 | tail -20 || true
echo "============================================================"

# --- exit non-zero if either testsuite had unexpected failures ---
if [ $newlibsts -ne 0 ] || [ $binutilssts -ne 0 ]; then
    echo "ERROR: testsuite had unexpected failures (gcc=$newlibsts, binutils=$binutilssts)"
    exit 1
fi

echo "INFO: all tests passed"
exit 0
