#!/bin/bash
# python-config script for Windows MinGW cross-compilation of GDB
# This script is used by GDB configure via --with-python=SCRIPT
# It provides the Windows Python include and library paths
# for the MinGW cross-compiler.
#
# GDB configure calls:
#   ${python_prog} ${srcdir}/python/python-config.py --includes
#   ${python_prog} ${srcdir}/python/python-config.py --ldflags
#   ${python_prog} ${srcdir}/python/python-config.py --exec-prefix
#
# where ${python_prog} is this script.  $1 is the python-config.py path
# (which we ignore), $2 is the option we care about.

PYTHON_PREFIX=/opt/nuclei/python38

# The first argument is the path to python-config.py, skip it
shift

case "$1" in
  --prefix | --exec-prefix)
    # Return empty to avoid defining WITH_PYTHON_PATH in GDB.
    # On Windows, Python finds Lib/ and DLLs/ relative to the DLL location.
    echo ""
    ;;
  --includes)
    echo "-I$PYTHON_PREFIX/include"
    ;;
  --libs)
    echo "-lpython38"
    ;;
  --ldflags)
    echo "-L$PYTHON_PREFIX/libs -lpython38"
    ;;
  --cflags)
    echo "-I$PYTHON_PREFIX/include"
    ;;
esac
exit 0