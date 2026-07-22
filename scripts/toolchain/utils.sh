#!/usr/bin/env bash

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)

tooltype=${TOOLTYPE:-}
toolhost=${TOOLHOST:-}
toolver=${TOOLVER:-}
vendor=${TOOLVENDOR:-nuclei}
dorebuild=${DOREBUILD:-}
dorelease=${DORELEASE:-}
ciarcloc=${CIARCLOC:-}

# toolchain source directory
toolsrcdir=$(readlink -f $SCRIPTDIR/../..)
# BUILDDATE is used to set toolver when TOOLVER is not specified
builddate=${BUILDDATE:-$(date -u +%Y%m%d)}
# If you want to fix the build directory name, you can set BUILDTAG variable
buildtag=${BUILDTAG:-$(date -u +%Y%m%d_%H%M%S)}
TOOLNAME=gcc

# share toolchain location for nuclei server to access
ShareLoc=${SHARELOC:-/home/share/devtools/toolchain/nuclei_gnu}

maketarget="newlib"
stripcmd="riscv64-unknown-elf-strip"
if [ "$tooltype" == "xnewlibc" ] ; then
    maketarget="newlib"
elif [ "x$tooltype" == "xglibc" ] ; then
    maketarget="linux"
    stripcmd="riscv64-unknown-linux-gnu-strip"
elif [ "x$tooltype" == "xmuslc" ] ; then
    maketarget="musl"
    stripcmd="riscv64-unknown-linux-musl-strip"
else
    tooltype="newlibc"
    maketarget="newlib"
fi

if [[ "$toolhost" != "win"* ]] && [ "x$toolhost" != "xlinux64" ] ; then
    if [ "x$dorelease" != "x1" ] ; then
        if cat /etc/issue | grep -i ubuntu ; then
            toolhost="win64"
        else
            toolhost="linux64"
        fi
    else
        toolhost="linux64"
    fi
fi

if [[ "$CI_PIPELINE_ID" =~ ^[0-9]+$ ]] ; then
    workroot=/Local/gitlab-runner/work
    if [ ! -d $workroot ] ; then
        echo "INFO: Maybe in docker environment now!"
        workroot=/work
    fi
    LocalBuilds=$workroot/toolchain/builds
    LocalInstalls=$workroot/toolchain/install
    if [ "x$doclean" == "x" ] ; then
        echo "Do clean build folder when sucessfully built"
        doclean=1
    fi
else
    LocalBuilds=$toolsrcdir/LocalBuilds
    LocalInstalls=$toolsrcdir/LocalInstall
    if [ "x$doclean" == "x" ] ; then
        echo "Don't clean build folder when sucessfully built"
        doclean=0
    fi
fi

LocalHostInstalls=${LocalInstalls}/${toolhost}/${tooltype}
LocalLinInstalls=${LocalInstalls}/linux64/${tooltype}
ShareInstalls=${ShareLoc}/${toolhost}/${tooltype}

tooltag=${toolhost}_${tooltype}
savebldenv=$(pwd)/lastbuild_${tooltag}.env
if [ "x$dorebuild" == "x1" ] ; then
    if [ ! -f $savebldenv ] ; then
        echo "ERROR: Could not find last build save variable file $savebldenv, please check!"
        exit 1
    fi
    echo "INFO: Source last build environment file $savebldenv"
    set -a
    source $savebldenv
    set +a
    if [ "x$toolprefix" == "x" ] || [ "x$toolbuilddir" == "x" ] ; then
        echo "ERROR: toolprefix or toolbuilddir is not provided in $savebldenv, please check!"
        exit 1
    fi
    if [ ! -f $toolbuilddir/Makefile ] ; then
        echo "ERROR: There is no Makefile in $toolbuilddir, please check!"
        exit 1
    fi
else
    if [ "x${CI_JOB_ID}" != "x" ] ; then
        toolbuildtag=pipeline${CI_PIPELINE_ID}_job${CI_JOB_ID}
    else
        toolbuildtag=$buildtag
    fi
    if [ "x$toolver" != "x" ] ; then
        toolver=$toolver
    elif [ "x${CI_JOB_ID}" != "x" ] ; then
        toolver=pipeline${CI_PIPELINE_ID}
    else
        toolver=$builddate
    fi
    builddirname=${toolver}_${tooltag}_${toolbuildtag}
    toolprefix=$LocalHostInstalls/${toolver}/$TOOLNAME
    lintoolprefix=$LocalLinInstalls/${toolver}/${TOOLNAME}
    toolbuilddir=$LocalBuilds/${builddirname}
    # only save environment when no do release
    if [ "x$dorelease" != "x1" ] ; then
        echo "INFO: Save build prefix and build directory environment variable to $savebldenv"
        echo "toolprefix=${toolprefix}" > $savebldenv
        echo "toolbuilddir=${toolbuilddir}" >> $savebldenv
        echo "toolver=${toolver}" >> $savebldenv
        echo "lintoolprefix=${lintoolprefix}" >> $savebldenv
        echo "builddirname=${builddirname}" >> $savebldenv
        echo "toolbuildtag=${toolbuildtag}" >> $savebldenv
    fi
fi
toolbasedir="${toolprefix}/.."

function prepare_buildenv() {
    if [[ "$toolhost" == "win"* ]] ; then
        echo "INFO: Add prebuilt linux host riscv toolchain $lintoolprefix into PATH"
        export PATH=$lintoolprefix/bin:$PATH
    else
        echo "INFO: Add prebuilt riscv toolchain $lintoolprefix into PATH"
        export PATH=$toolprefix/bin:$PATH
    fi
}

function symlink_gcc_prereq() {
    local req=$1

    if [ "x$req" == "x" ] ; then
        return
    fi
    if [ -L $req ] ; then
        echo "Remove existing symolic link $req"
        rm -f $req
    fi
    if [ ! -L $req ] ; then
        echo "Do symlink ../gcc/$req -> $req"
        ln -s -f ../gcc/$req .
    fi
}

function prepare_prerequisites() {
    pushd $toolsrcdir/gcc
    # required by gdb 14.x now, see https://sourceware.org/git/?p=binutils-gdb.git;a=commit;h=991180627851801f1999d1ebbc0e569a17e47c74
    echo "Prepare gcc and gdb prerequisites"
    if [ -f contrib/download_prerequisites ] ; then
        if ./contrib/download_prerequisites ; then
            echo "Successfully downloaded gcc prerequisites!"
            pushd $toolsrcdir/gdb
            echo "Make symlink to gcc gmp and mpfr prerequisites for gdb"
            symlink_gcc_prereq gmp
            symlink_gcc_prereq mpfr
            symlink_gcc_prereq isl
            popd
        else
            echo "ERROR: failed to download gcc prerequisites"
        fi
    fi
    popd
}

function describe_repo() {
    local repodir=${1}
    local repodesc=${2:-gitrepo.txt}

    if [ -d ${repodir}/.git ] ; then
        pushd ${repodir}
        echo "toolchain repo commit: $(git describe --always --abbrev=10 --dirty)" > ${repodesc}
        git log --oneline -1 >> ${repodesc}
        git submodule >> ${repodesc}
        if [ -d ${repodir}/libncrt/.git ] ; then
            pushd libncrt
            echo "libncrt repo commit: $(git describe --always --abbrev=10 --dirty)" >> ${repodesc}
            git log --oneline -1 >> ${repodesc}
            popd
        fi
        popd
    else
        echo "not a git repo" > ${repodesc}
    fi
}

function describe_build() {
    local builddesc=${1:-build.txt}

    local buildstamp="Build timestamp: $(date --utc +%s)"
    if [ "x${CI_JOB_ID}" != "x" ] ; then
        buildstamp="$buildstamp, pipeline id: ${CI_PIPELINE_ID}, job id: ${CI_JOB_ID}"
    fi
    echo $buildstamp > ${builddesc}
    date >> ${builddesc}
}

function collect_build_logfiles() {
    local logdir=${1:-logs}
    local builddir=${2:-$toolbuilddir}

    local buildname=$(basename $builddir)

    mkdir -p $logdir

    local logbuildzip=$(readlink -f $logdir)/${buildname}.zip


    if [ -f $logbuildzip ] ; then
        echo "Remove existing $logbuildzip"
        rm -f $logbuildzip
    fi
    echo "Collect all found *.log in $builddir and zip to $logbuildzip"
    pushd $builddir
    find . -name "*.log" | xargs zip $logbuildzip
    popd
}

function cleanup_build() {
    local cleaninstall=${1:-}
    local dir2rm=$LocalBuilds/${toolver}_${tooltag}_*
    echo "INFO: Remove all build related directories for $toolver, ${toolhost}, ${tooltype} in $dir2rm"
    rm -rf $dir2rm
    local tooldir=$(readlink -f $toolbasedir)
    if [ "x$tooldir" != "x" ] && [ "x$cleaninstall" == "x1" ] ; then
        echo "INFO: Remove all installed toolchain for $toolver in $tooldir"
        rm -rf $tooldir
    else
        echo "INFO: Will not remove installed toolchain for $toolver in $tooldir"
    fi
    return 0
}

function copy_ci_artifact() {
    local artifact=$1

    if [ "x$ciarcloc" == "x" ] || [ "x$artifact" == "x" ] ; then
        return
    fi
    if [ ! -d $ciarcloc ] || [ ! -f $artifact ]; then
        echo "WARN:$ciarcloc or $artifact not exist, can't copy $artifact to $ciarcloc!"
        return
    fi
    echo "Copy ci artifact $artifact to $ciarcloc"
    command cp -f $artifact $ciarcloc
}

function md5sum_folder() {
    local fld2md=${1:-.}

    if [ -d $fld2md ] ; then
        echo "Do md5sum on files existing in $fld2md directory"
        find $fld2md -maxdepth 1 -type f -not -name "md5sum.txt" | xargs md5sum | tee $fld2md/md5sum.txt
    fi
}

function gitarchive() {
    local repotgz=$1
    if which git-archive-all > /dev/null 2>&1 ; then
        git-archive-all ${repotgz}
    else
        git ls-files --recurse-submodules | tar --ignore-failed-read --quoting-style=locale -czf ${repotgz} -T-
    fi
}

function archive_gitrepo() {
    local repodir=${1:-${toolsrcdir}}
    local repotgz=${2:-${toolbasedir}/source.tar.gz}
    if [ -d ${repodir}/.git ] ; then
        pushd ${repodir}
        command rm -f ${repotgz}
        echo "Archive source code to ${repotgz}"
        gitarchive $repotgz
        popd
    else
        echo "Not a git repo"
    fi
}

# install libncrt to toolchain for linux and windows
# rake conf=$bldcfg build_dir="build" out_dir="out" install only works for linux
# so create this for win and linux
function install_libncrt() {
    local libncrtout=${1:-$toolsrcdir/libncrt/out}
    local bldcfg=${2:-riscv64-unknown-elf}

    local libncrtinstdir="${toolprefix}/${bldcfg}"
    echo "Install libncrt library from $libncrtout to $libncrtinstdir"
    pushd $libncrtout
    command cp -rf * ${libncrtinstdir}
    popd
}

# TODO: need to check build is pass or fail
# currently rake task always return 0 even fail, need to fix it in libncrt repo
function build_libncrt() {
    local repodir=${1:-$toolsrcdir/libncrt}
    local bldcfg=${2:-riscv64-unknown-elf}
    local libncrtczf=${3}

    if [ -d $repodir ] ; then
        pushd $repodir
        # build libncrt library
        echo "Clean previous build for libncrt"
        rm -rf build out build_libncrt.log
        if ! rake --version ; then
            echo "ERROR: Ruby Rake not present, please install it first!"
            popd
            return 1
        fi
        echo "Build libncrt for conf $bldcfg, library generated into out, build objects into build"
        rake conf=$bldcfg build_dir="build" out_dir="out" >build_libncrt.log 2>&1
        echo "Backup libncrt build log build_libncrt.log to $toolbuilddir"
        cp -f build_libncrt.log $toolbuilddir/
        # check the build log to see whether build libncrt library is pass or fail
        if cat build_libncrt.log | grep "rake aborted" > /dev/null ; then
            echo "ERROR: Failed to build libncrt for conf $bldcfg!"
            popd
            return 1
        fi
        if [ "x$libncrtczf" != "x" ] ; then
            libncrtdir=$(dirname $libncrtczf)
            mkdir -p $libncrtdir
            command rm -f $libncrtczf
            tar --owner=0 --group=0 --numeric-owner --transform "s/^out/libncrt/" -czf $libncrtczf out
        fi
        # install libncrt library
        install_libncrt $repodir/out
        popd
    else
        echo "WARN: libncrt repo $repodir not exist!"
    fi
    return 0
}

function install_libncrt_doc() {
    local repodir=${1:-$toolsrcdir/libncrt}
    local dstdir=${2:-$toolprefix/share/pdf}

    mkdir -p $dstdir

    echo "Install libncrt doc into $dstdir"
    command cp -f $repodir/doc/*.pdf $dstdir
    echo "Install libncrt sample code into $dstdir"
    local samplecodefile=$repodir/emrun/Src/fileops_uart.c
    if [ -f $samplecodefile ] ; then
        command cp -f $samplecodefile $dstdir/libncrt_fileops_reference.c
    fi
}

function tar_toolchain() {
    local tooldir=$1

    if [ ! -d "$tooldir/bin" ] ; then
        echo "Prebuilt toolchain doesn't exist in $tooldir!"
        return
    fi
    local toolname=${2:-$(basename $tooldir)}
    echo "Archive toolchain in $tooldir to $toolname.tar.bz2"

    command rm -f ${toolname}.tar.bz2
    tar -jcf ${toolname}.tar.bz2 -C $(dirname $tooldir) $(basename $tooldir)
    copy_ci_artifact ${toolname}.tar.bz2
}

function zip_toolchain() {
    local tooldir=$1

    if [ ! -d "$tooldir/bin" ] ; then
        echo "Prebuilt toolchain doesn't exist in $tooldir!"
        return
    fi
    local toolname=${2:-$(basename $tooldir)}

    pushd $(dirname $tooldir)
    echo "Archive toolchain in $tooldir to $toolname.zip"
    command rm -f ${toolname}.zip
    zip -9 -q -r ${toolname}.zip $(basename $tooldir)
    copy_ci_artifact ${toolname}.zip
    popd
}

function archive_toolchain() {
    local tooldir=${toolprefix}
    local basedir=$(readlink -f ${toolbasedir})
    local toolname=$basedir/${vendor}_riscv_${tooltype}_prebuilt_${toolhost}_$(basename $basedir)

    if [[ "$toolhost" == "win"* ]] ; then
        zip_toolchain $tooldir $toolname
    else
        tar_toolchain $tooldir $toolname
    fi
    # calculate md5sum when toolchain is archived
    md5sum_folder $basedir
}

function strip_toolchain() {
    local tooldir=${1:-${toolprefix}}

    pushd $tooldir
    szbefore=$(du -sh . | cut -f1)
    echo "Toolchain size before stripped is $szbefore"
    for chkdir in bin libexec lib lib64 sysroot riscv* ; do
        for fnd in `find $chkdir -type f \( -executable -o -name "*.so*" -o -name "*.a" -o -name "*.o" \) 2>/dev/null` ; do
            if [ -L $fnd ]; then
                continue
            fi
            filetype=$(file $fnd | cut -d ":" -f2)
            fndtype="linexe"
            if echo "$filetype" | grep -q "PE.* executable" ; then
                fndtype="winexe"
            elif echo "$filetype" | grep -q "ELF" ; then
                fndtype="linexe"
                ## centos 6.10 file version is 5.04 which cannot determine RISC-V elf, so we use readelf to handle this
                #if echo "$filetype" | grep -q "RISC-V" ; then
                ## centos 6.10 readelf version 2.30-55.el6.2 works and can get RISC-V machine tag
                if readelf -h $fnd 2>&1 | grep -q "Machine: * RISC-V" ; then
                    fndtype="riscvexe"
                fi
            elif echo "$filetype" | grep -q "ar archive" ; then
                fndtype="ar"
                if readelf -h $fnd 2>&1 | grep -q "Machine: * RISC-V" ; then
                    fndtype="riscvar"
                fi
            else
                continue
            fi
            orgfilesz=$(stat -c %s $fnd)
            # not using try loop like previous commit because strip may work wrong on riscv elf
            scmd="strip"
            if [[ $fndtype == riscv* ]] ; then
                scmd=${stripcmd}
            fi
            # options to strip comments
            ## strip out extra .comment and .note for gwarf-4 debug newlib/libgcc/libstdc++ can decrease size from 7.1G to 3.1G
            ## otherwise it will decrease size from 7.3G to 3.1G, so we can keep .comment and .note
            #stripcmtopt="--remove-section=.comment --remove-section=.note"
            stripcmtopt=""
            if [[ $fnd == *.a ]] ; then
                stripopt="-g --enable-deterministic-archives $stripcmtopt"
            elif [[ $fnd == *.o ]] ; then
                stripopt="-g $stripcmtopt"
            elif [[ $fnd == *.so* ]] ; then
                stripopt="--strip-unneeded $stripcmtopt"
            else
                stripopt="--strip-unneeded $stripcmtopt"
            fi
            $scmd $stripopt $fnd 2>&1 | grep -q "format"
            sret=$?
            # strip command always return 0, so we need to use grep to check whether strip pass
            # grep file format not recognized
            # grep Unable to recognise the format of the input file
            if [ "x$sret" == "x1" ] ; then
                stripfilesz=$(stat -c %s $fnd)
                if [ "$stripfilesz" == "$orgfilesz" ] ; then
                    echo "Unstripped $fnd, type $fndtype using $scmd $stripopt, size unchanged, ${stripfilesz} bytes"
                    continue
                fi
                #decpct=$(echo "scale=3; 100 * ($orgfilesz - $stripfilesz) / $orgfilesz" | bc)
                decpct=$(awk "BEGIN {printf \"%.2f\", 100 * ($orgfilesz - $stripfilesz) / $orgfilesz}")
                echo "Stripped $fnd, type $fndtype using $scmd $stripopt, size decreased from $orgfilesz to $stripfilesz bytes by ${decpct}%"
            fi
        done
    done
    szafter=$(du -sh . | cut -f1)
    echo "Toolchain size stripped from $szbefore to $szafter"
    popd
}

function install_runtime_bundle() {
    echo "INFO: Install runtime bundle to $toolprefix/lib"
    mkdir -p $toolprefix/lib
    if [[ "$toolhost" == "win64" ]] ; then
        # Bundle Windows runtime DLLs alongside gdb binary
        # Windows finds python38.dll, Lib/ and DLLs/ in the same directory
        if [ "x$dopython" == "x1" ] ; then
            PYTHON_PREFIX=/opt/nuclei/python38
            if [ -f "$PYTHON_PREFIX/python38.dll" ] ; then
                echo "INFO:   Bundling python38.dll and related files"
                cp -f $PYTHON_PREFIX/python38.dll $toolprefix/bin/
                cp -f $PYTHON_PREFIX/python3.dll $toolprefix/bin/
                cp -f $PYTHON_PREFIX/vcruntime140.dll $toolprefix/bin/
                cp -f $PYTHON_PREFIX/vcruntime140_1.dll $toolprefix/bin/
                # Copy standard library and extension modules from NuGet package
                cp -rf $PYTHON_PREFIX/Lib $toolprefix/bin/
                cp -rf $PYTHON_PREFIX/DLLs $toolprefix/bin/
            else
                echo "WARN: python38.dll not found in $PYTHON_PREFIX, skip python bundle!"
            fi
        fi
    else
        # Linux bundle logic (existing)
        # Bundle runtime libs from the build environment (CentOS 7 with devtoolset-9, rh-python38)
        # These are bundled so gdb and its Python C extensions can run on other Linux distros
        # without needing these libs to be installed on the target system.
        for lib in libncursesw.so.5 libtinfo.so.5 libffi.so.6 libsqlite3.so.0 libpanelw.so.5 libreadline.so.6 ; do
            local src=$(find /lib64 /usr/lib64 /usr/lib -name "$lib" -maxdepth 3 2>/dev/null | head -1)
            if [ -f "$src" ] ; then
                cp -Lf "$src" $toolprefix/lib/
                echo "INFO:   Bundled $lib"
            fi
        done
        # Set RUNPATH on bundled .so files so they can find each other
        for lib in $toolprefix/lib/*.so* ; do
            if [ -f "$lib" ] && [ -x "$lib" ] ; then
                patchelf --set-rpath '$ORIGIN' "$lib" 2>/dev/null || true
            fi
        done
        # Bundle python libs if python support is enabled
        if [ "x$dopython" == "x1" ] ; then
            local pyrun=$PYTHON_PREFIX/bin/python3
            if [ ! -f $pyrun ] ; then
                echo "WARN: Python3 not found in $PYTHON_PREFIX, skip python bundle!"
            else
                cp -f $PYTHON_PREFIX/lib/libpython3.8.so.1.0 $toolprefix/lib/
                cp -f $PYTHON_PREFIX/lib/libpython3.8.so $toolprefix/lib/
                cp -rf $PYTHON_PREFIX/lib/python3.8 $toolprefix/lib/python3.8
            fi
        fi
        # Set RUNPATH on gdb, run, and other binaries to find bundled libs
        for bin in $(ls $toolprefix/bin/*-gdb $toolprefix/bin/*-run 2>/dev/null) ; do
            if [ -f "$bin" ] && which patchelf > /dev/null 2>&1 ; then
                echo "INFO: Set RUNPATH on $bin to find bundled libs"
                patchelf --set-rpath '$ORIGIN/../lib' $bin
            fi
        done
        if [ "x$dopython" == "x1" ] ; then
            local libpython=$toolprefix/lib/libpython3.8.so.1.0
            if [ -f "$libpython" ] && which patchelf > /dev/null 2>&1 ; then
                echo "INFO: Set RUNPATH on $libpython for bundled libs"
                patchelf --set-rpath '$ORIGIN' $libpython
            fi
            local dynload_dir=$toolprefix/lib/python3.8/lib-dynload
            if [ -d "$dynload_dir" ] ; then
                for f in $dynload_dir/*.so ; do
                    [ -f "$f" ] && patchelf --set-rpath '$ORIGIN/../..' "$f"
                done
                echo "INFO: Set RUNPATH on Python C extensions for bundled libs"
            fi
        fi
    fi
    echo "INFO: Runtime bundle installed to $toolprefix/lib"
}

function show_toolchain() {
    local basedir=$(readlink -f ${toolbasedir})

    echo "INFO: Show installed toolchain content."
    ls -lh ${basedir}
}

function sync_toolchain() {
    local localinstall=${1:-${toolbasedir}}
    local symlink=${2:-}
    if [ ! -d ${localinstall} ] ; then
        echo "ERROR: local toolchain directory ${localinstall} not exist!"
        return 1
    else
        localinstall=$(readlink -f $localinstall)
    fi

    if [ ! -d ${ShareLoc} ] ; then
        echo "ERROR: $ShareLoc directory not exist, maybe you are in docker environment!"
        return 1
    fi

    if [ ! -d ${ShareInstalls} ] ; then
        echo "INFO: Create share toolchain install directory ${ShareInstalls}"
        mkdir -p ${ShareInstalls}
    fi
    local basedir=$(basename ${localinstall})
    if [ -d ${ShareInstalls}/${basedir} ] ; then
        echo "INFO: Removing existing ${ShareInstalls}/${basedir}"
        rm -rf ${ShareInstalls}/${basedir}
    fi
    if [ -f $localinstall/md5sum.txt ] ; then
        echo "INFO: Check content of md5sum.txt"
        cat $localinstall/md5sum.txt
    fi
    echo "INFO: Copy $localinstall to $ShareInstalls"
    command cp -rf ${localinstall} ${ShareInstalls}
    echo "INFO: Toolchain copied to ${ShareInstalls}/${basedir}"
    if [ "x$symlink" != "x" ] ; then
        pushd ${ShareInstalls}
        echo "INFO: Symbolic link from ${basedir} -> ${symlink} in ${ShareInstalls}"
        rm -f $symlink
        command ln -sf $basedir $symlink
        popd
    fi
    return 0
}
