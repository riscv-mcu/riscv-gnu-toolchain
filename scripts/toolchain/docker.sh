#!/usr/bin/env bash

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)

# enviroment variables
dockerrepo=${DOCKERREPO:-}
# when remote docker image is updated, pass PULLFIRST=1
# eg. PULLFIRST=1 bash scripts/toolchain/docker.sh win64
pullfirst=${PULLFIRST:-}

# arguments
# arg 1: toolchain to be built for, default linux64, otherwise will be win64
# arg 2: docker image tag, default v2
toolhost=${1:-linux64}
imgtag=${2:-v2}

# toolchain source directory
toolsrcdir=$(readlink -f $SCRIPTDIR/../..)

winbuildimg=gnutoolchain-ubuntu20.04
linbuildimg=gnutoolchain-centos7

if [ "x$dockerrepo" == "x" ] ; then
    dockerrepo=docker.io/nucleisoftware
    if [[ $(hostname) == wh* ]] ; then
        if ping -qc 2 rego > /dev/null 2>&1; then
            dockerrepo=rego.corp.nucleisys.com/software
        fi
    fi
fi

dockercmd=podman
if which docker > /dev/null 2>&1 ; then
    dockercmd=docker
fi

echo "INFO: Using docker server: $dockerrepo"

function pull_image() {
    local imgrepo=$1
    echo "INFO: Pull image $imgrepo"
    $dockercmd pull $imgrepo
}

function run_image() {
    local imgrepo=$1
    shift
    local runcmd=$@
    echo "INFO: Run image $imgrepo, with $toolsrcdir mapping to /work, run command: $runcmd"
    local execmd="$dockercmd run -it -v ${toolsrcdir}:/work $imgrepo $runcmd"
    echo "CMD: $execmd"
    $execmd
}


img2run=$dockerrepo/$linbuildimg:$imgtag
runcmd="scl enable devtoolset-9 rh-python38 bash"

if [[ "$toolhost" == "win"* ]] ; then
    echo "WARN: If you are build $toolhost toolchain, you need to add linux prebuilt riscv toolchain to PATH in docker enviroment!"
    img2run=$dockerrepo/$winbuildimg:$imgtag
    runcmd="bash"
else
    toolhost="linux64"
fi

if [ "x$pullfirst" == "x1" ] ; then
    echo "INFO: pull $img2run first!"
    pull_image $img2run
fi

echo "INFO: Run docker image for build toolchain for $toolhost environment"
run_image $img2run $runcmd
