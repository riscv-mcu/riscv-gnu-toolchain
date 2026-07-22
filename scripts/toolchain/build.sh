#!/usr/bin/env bash

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)

# environment variables such as
# TOOLTYPE: newlibc or glibc
# TOOLHOST: win32, win64 or linux64, guess by docker os type(centos or ubuntu)
# TOOLVER: default will be build date timestamp, such as 20230406_104544
# MULTILIBGEN: multilib gen configuration
# DOLIBDEBUG: enable debug information when build library such as newlibc/glibc, default no
# DOMULTILIB: enable multilib build, default yes
# DOSTRIP: strip binary or not, default yes
# DOCONF: configure toolchain or not, default yes
# DOBUILD: build toolchain or not, default yes
# DOREBUILD: rebuild toolchain using last build environment, will not configure toolchain, default no
# DOLLVM: build llvm or not, default yes
# DODOC: build toolchain doc, default no
# DOCLEAN: clean toolchain build directory after sucessfully built, default no
# DOCLEANPREFIX: clean toolchain install prefix directory if existed, default no
# DOLIBNCRT: build libncrt for newlibc toolchain, default yes
# LIBNCRTBLDCFG: libncrt build config, default riscv64-unknown-elf
# DOARCHIVE: archive built toolchain and its source code, default no
# DEFRVCFG: default riscv configuration such arch/abi/tune/isa-spec configure when build gcc
# DOPYTHON: enable python support for GDB, 0 or 1, default 0
# JOBS: build jobs, default 16
tooltype=${TOOLTYPE:-newlibc}
toolhost=${TOOLHOST:-}
toolver=${TOOLVER:-}
multilibgen=${MULTILIBGEN:-}
dolibdebug=${DOLIBDEBUG:-}
domultilib=${DOMULTILIB:-}
doconf=${DOCONF:-1}
dorebuild=${DOREBUILD:-}
dostrip=${DOSTRIP:-1}
dollvm=${DOLLVM:-1}
dobuild=${DOBUILD:-1}
doarchive=${DOARCHIVE:-0}
dolibncrt=${DOLIBNCRT:-1}
libncrtbldcfg=${LIBNCRTBLDCFG:-riscv64-unknown-elf}
dodoc=${DODOC:-0}
doclean=${DOCLEAN:-}
docleanprefix=${DOCLEANPREFIX:-}
defrvcfg=${DEFRVCFG:-"--with-arch=rv64imc --with-abi=lp64"}
dopython=${DOPYTHON:-0}
jobs=${JOBS:-16}

# command arguments
# arg 1: first argument is the toolchain configure options
confopts=${1:-}

## sample usage
## Use case 1:
## You can copy scripts/toolchain/buildenv.sample to build.env
## and then modify the build.env as you expected, then source this environment file
# $ BUILDENV=build.env source scripts/toolchain/setup_env.sh
## then build this toolchain as you want
# $ ./scripts/toolchain/build.sh
## you can overwrite some predefined variable like this, for example, you want to change TOOLVER to 2023.04
# $ TOOLVER=2023.04 ./scripts/toolchain/build.sh
## Use case 2:
## This command below will build toolchain, document and libncrt, and toolchain version set to 2023.04, configure options used extra followed by build.sh
## when toolchain build successfully, it will archive the built toolchain, and clean this build, tool host is guess by docker image os environment
# $ DOLIBNCRT=1 DOARCHIVE=1 DOBUILD=1 DODOC=1 DOCLEAN=1 TOOLVER=2023.04 ./scripts/toolchain/build.sh "rv32emc-ilp32e--;rv32emac-ilp32e--;rv32imc-ilp32--;rv32imac-ilp32--;rv32imafc-ilp32f--;rv32imafdc-ilp32d--;rv64imac-lp64--;rv64imafc-lp64f--;rv64imafdc-lp64d--;"

source $SCRIPTDIR/utils.sh

echo "INFO: Build for $toolhost machine, library type $tooltype in 3s"
sleep 3

if [ ! -d $toolbuilddir ] ; then
    echo "WARN: Create local build folder $toolbuilddir for toolchain build"
    mkdir -p $toolbuilddir
fi

# Clean install prefix folder if required
if [ "x$docleanprefix" == "x1" ] ; then
    if [ -d $toolprefix ] ; then
        echo "INFO: Remove existing install folder for toolchain"
        rm -rf $toolprefix
    fi
fi

if [ ! -d $toolprefix ] ; then
    echo "WARN: Create local install folder for toolchain installation"
    mkdir -p $toolprefix
fi

if [ "x$toolhost" == "xwin32" ] ; then
    echo "INFO: Configure for windows 32bit host build"
    confopts="--with-host=i686-w64-mingw32 $confopts"
elif [ "x$toolhost" == "xwin64" ] ; then
    echo "INFO: Configure for windows 64bit host build"
    confopts="--with-host=x86_64-w64-mingw32 $confopts"
fi

if [ "x$dollvm" == "x1" ] ; then
    echo "INFO: Enable llvm build"
    confopts="--enable-llvm $confopts"
fi

if [ "x$dodoc" == "x1" ] ; then
    echo "INFO: Enable toolchain doc build"
    confopts="--enable-doc $confopts"
fi

if [ "x$dopython" == "x1" ] ; then
    if [ "x$toolhost" == "xlinux64" ] ; then
        PYTHON_PREFIX=/opt/nuclei/python38
        echo "INFO: Enable GDB python support with $PYTHON_PREFIX (linux host)"
        confopts="--with-python=$PYTHON_PREFIX/bin/python3 $confopts"
        # --with-python-libdir and LDFLAGS are passed via GDB_TARGET_FLAGS_EXTRA
        # so they go directly to gdb's configure, not the top-level configure
        export GDB_TARGET_FLAGS_EXTRA="--with-python-libdir=${toolprefix}/lib LDFLAGS=\"-L${PYTHON_PREFIX}/lib -Wl,--enable-new-dtags,-rpath,${toolprefix}/lib\""
    elif [ "x$toolhost" == "xwin64" ] ; then
        PYTHON_PREFIX=/opt/nuclei/python38
        echo "INFO: Enable GDB python support with $PYTHON_PREFIX (windows host)"
        confopts="--with-python=${PYTHON_PREFIX}/python-config-mingw.sh $confopts"
    else
        echo "WARN: GDB python support only available for linux64 and win64 host, skip!"
        dopython=0
    fi
fi

if [ "x$dolibdebug" == "x1" ] ; then
    echo "INFO: Enable build library such as newlibc/glibc with debug information"
    confopts="--enable-debug-info $confopts"
fi

# Handle multilib configuration
# Priority: 1) DOMULTILIB=0 disables multilib; 2) confopts has --with-multilib-generator;
#           3) MULTILIBGEN env var; 4) default multilib
if [ "x$domultilib" == "x1" ] ; then
    if [[ "$confopts" =~ "--with-multilib-generator" ]] ; then
        echo "INFO: multilib-generator configuration present in passed configure options!"
    elif [ "x$multilibgen" != "x" ] ; then
        echo "INFO: Enable multilib generator of $multilibgen"
        confopts="$confopts --enable-multilib --with-multilib-generator=$multilibgen"
    else
        echo "INFO: Enable multilib build with default multilib configuration"
        confopts="$confopts --enable-multilib"
    fi
else
    echo "INFO: Disable multilib build"
fi

if [[ ! "$confopts" =~ "--with-arch=" ]] && [[ "x$defrvcfg" =~ "--with-arch=" ]] ; then
    echo "INFO: Use default arch/abi/isaspec/tune config: $defrvcfg"
    confopts="$confopts $defrvcfg"
fi

# Save build environment variables
${SCRIPTDIR}/save_env.sh savebuild_${toolhost}_${tooltype}.env

echo "INFO: Change directory to build folder $toolbuilddir"
pushd $toolbuilddir

echo "INFO: Generate build stamp and repo information into $toolprefix"
describe_repo "$toolsrcdir" "$toolprefix/gitrepo.txt"

if [ "x$dorebuild" == "x1" ] ; then
    echo "WARN: Rebuild toolchain in $toolbuilddir now, will not do toolchain configure!"
else
    describe_build "$toolprefix/build.txt"
    if [ "x$doconf" == "x1" ] ; then
        echo "INFO: Do configure and install to $toolprefix, configure command as below!"
        confcmd="${toolsrcdir}/configure --prefix=${toolprefix} ${confopts}"
        echo "INFO: ${confcmd}"
        # save configure command to build.txt
        echo "Configure command: ${confcmd}" >> $toolprefix/build.txt
        $confcmd
    else
        echo "INFO: Will not do toolchain configure!"
    fi
fi

# Prepare build environment
prepare_buildenv
prepare_prerequisites

if [ "x$dobuild" == "x1" ] ; then
    echo "INFO: Do toolchain build for target $maketarget in 3s"
    sleep 3
    make -j${jobs} ${maketarget}
else
    echo "WARN: Will not build toolchain in $toolbuilddir"
fi
dosuc=$?

echo "INFO: toolchain build status $dosuc"

if [ "x$dostrip" == "x1" ] && [ -d $toolprefix/bin ] ; then
    echo "INFO: Strip toolchain in $toolprefix"
    strip_toolchain
    #make strip
else
    echo "INFO: Toolchain is not stripped"
fi
# exit from build directory
popd

if [ "x$tooltype" == "xnewlibc" ] && [ "x$dolibncrt" == "x1" ] && [ "x$dosuc" == "x0" ]; then
    if ls $toolprefix/bin/*-gcc* > /dev/null 2>&1 ; then
        echo "INFO: Build nuclei c runtime library for $tooltype toolchain"
        if [ "x$toolhost" == "xlinux64" ] ; then
            echo "INFO: Setup toolchain PATH for build libncrt"
            export PATH=$toolprefix/bin:$PATH
        fi
        if [ -d $toolsrcdir/libncrt ] ; then
            libncrtczf=$toolbasedir/nuclei_libncrt.tar.gz
            echo "INFO: libncrt library will not archived as $libncrtczf if not build successfully"
            build_libncrt $toolsrcdir/libncrt $libncrtbldcfg $libncrtczf
            # get return code of build libncrt to know build is pass or fail
            dosuc=$?
            if [ "x$dodoc" == "x1" ] && [ "x$dosuc" == "x0" ]; then
                echo "INFO: Install libncrt doc into $toolprefix/share/pdf"
                install_libncrt_doc $toolsrcdir/libncrt $toolprefix/share/pdf
            fi
        else
            echo "WARN: libncrt source code not exist, will not build it!"
        fi
    else
        echo "WARN: Toolchain is not built, will not build nuclei c runtime library!"
    fi
fi

# Install runtime bundle (runtime libs and python if enabled), for linux and windows host
if [ "x$dosuc" == "x0" ] ; then
    echo "INFO: Install runtime bundle to $toolprefix"
    install_runtime_bundle
fi

collect_build_logfiles logs

if [ "x$doclean" == "x1" ]  ; then
    if [ "x$dosuc" == "x0" ] ; then
        echo "INFO: Clean build directory in $toolbuilddir"
        rm -rf $toolbuilddir
    else
        if [[ "$CI_PIPELINE_ID" =~ ^[0-9]+$ ]] ; then
            echo "ERROR: Toolchain build is failing in ci pipeline, to reduce disk usage, will remove build directory, please check logfile collected in logs/"
            rm -rf $toolbuilddir
        else
            echo "ERROR: Toolchain build is failing, will not remove build directory, please check $toolbuilddir"
        fi
    fi
else
    echo "INFO: Find the build directory in $toolbuilddir, remove it by yourself!"
fi
if [ "x$dosuc" == "x0" ] ; then
    if [ "x$doarchive" == "x1" ] ; then
        echo "INFO: Archive the toolchain source code and built toolchain in $toolprefix!"
        archive_gitrepo
        archive_toolchain
        show_toolchain
    fi
    if [ "x$dobuild" == "x1" ]; then
        echo "INFO: Find successful build artifacts in the install directory in $toolprefix"
    else
        echo "INFO: Toolchain is not built, there might be nothing in $toolprefix"
    fi
else
    echo "ERROR: Toolchain build failing, see build artifacts in the install directory in $toolprefix"
fi

exit $dosuc
