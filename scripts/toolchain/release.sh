#!/usr/bin/env bash

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)

toolloc=${TOOLLOC:-}

symlink=${1:-}

if [ "x$toolloc" == "x" ] ; then
    if [ "x$TOOLVER" == "x" ] ; then
        echo "INFO: Sync last build version toolchain"
        DORELEASE=1 DOREBUILD=1 source $SCRIPTDIR/utils.sh
    else
        echo "INFO: Sync toolchain version $TOOLVER"
        DORELEASE=1 source $SCRIPTDIR/utils.sh
    fi
    toolloc=$toolbasedir
else
    echo "INFO: Using toolchain located in $toolloc"
    DORELEASE=1 source $SCRIPTDIR/utils.sh
fi

echo "INFO: Sync toolchain for $toolhost-$tooltype located in $(readlink -f $toolloc)"
echo "INFO: Doing sync toolchain in 3 seconds..."
sleep 3
if sync_toolchain $toolloc $symlink ; then
    echo "INFO: Sync toolchain done!"
    # show released toolchain version and repo information,
    # see it from the end of the release log
    # toolloc is the toolchain basedir, toolchain binaries and gitrepo.txt
    # are installed in the <TOOLNAME>(gcc) subdirectory
    show_toolchain_version $toolloc/gcc/bin $toolloc/gcc/gitrepo.txt
    exit 0
else
    echo "ERROR: Sync toolchain failed!"
    exit 1
fi
