#!/usr/bin/env bash

for enval in TOOLTYPE TOOLHOST TOOLVER MULTILIBGEN DOMULTILIB \
    DOCONF DOSTRIP DOLLVM DOBUILD DOARCHIVE DOLIBNCRT DOLIBDEBUG \
    LIBNCRTBLDCFG DODOC DOCLEAN DEFRVCFG DOPYTHON JOBS DOREBUILD ; do
    unset $enval
done

# how to use
# the below command will setup build environment variables defined in /path/to/your_build.env
# the variables are used by scripts/toolchain/build.sh
# a sample build.env file could be find in scripts/toolchain/buildenv.sample, you can copy it and modify to your one
# BUILDENV=/path/to/your_build.env source scripts/toolchain/setup_env.sh
# If you want to unset all the variables, just pass a not exist BUILDENV file

# environment variables
# BUILDENV: build environment variable file
buildenv=${BUILDENV:-build.env}

echo "INFO: Unset all the build related environment variables"

if [ -f $buildenv ] ; then
    buildenv=$(readlink -f $buildenv)
    echo "INFO: Source environment variables from $buildenv"
    echo "INFO: Content show as below:"
    cat $buildenv
    # the set -a command enables automatic exporting of all subsequently defined variables
    set -a
    source $buildenv
    set +a
    echo "INFO: $buildenv is sourced, you can check the environment variables now!"
else
    echo "WARN: No build.env found in $(pwd)"
fi
