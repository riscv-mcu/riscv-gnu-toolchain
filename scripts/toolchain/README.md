# How to build riscv toolchain for Nuclei RISC-V Processor

> [!NOTE]
> We dont provide any support regarding build toolchain, all toolchain building
> related source code and scripts are open source, same as the one used internally.

This directory contains scripts required for building riscv toolchain
of Nuclei RISC-V processor.

About how to pull docker image and get source code, please check https://github.com/riscv-mcu/riscv-gnu-toolchain/issues/24

The toolchain prefix is named `riscv64-unknown-elf-` for newlibc toolchain,
and `riscv64-unknown-linux-gnu-` for glibc toolchain now, which is
incompatiable with previous 2022.12 or earlier version of Nuclei
riscv toolchain name `riscv-nuclei-elf` for newlibc and `riscv-nuclei-linux-gnu-`
for glibc.

## Support Host and Requirements

> [!NOTE]
> You are developing toolchain, you always need good network connection, you can use
> vpn or other method to solve the network issue, since toolchain building need to download
> prerequisites from internet

- Tested on Ubuntu 20.04, real machine not docker environment
- Git, docker or podman is required
- Good network connection to github.com and gcc.gnu.org, since most source code are pulled from there

## Directory contents

> [!NOTE]
> - All the scripts below are developed by Nuclei, used as internal toolchain build and release scripts,
>   since many customer want to modify toolchain by themselves, so we just open source these scripts,
>   but we dont provide any support for these scripts, please look into the script source code by yourself.
> - The script itself is just wrapper for configure, build and release toolchain as described in the repo's
>   itself's README.md.

- `prepsrc.sh`: use it in host, prepare source code include libncrt
- `docker.sh`: use it in host, download docker image, and run it for building windows or linux toolchain
- `setup_env.sh`: use it in docker, script used to setup build toolchain environment
- `build.sh`: use it in docker, script used to build toolchain
- `release.sh`: use it in host, release the toolchain to nuclei share environment folder,
   used by Nuclei engineer only
- `cleanup.sh`: use it in docker, cleanup build directory and local installed toolchain for selected version
- `utils.sh`: utilities used by other scripts
- `test.sh`: WIP, not yet ready

## Prepare source code

If you want to build this toolchain, you can clone source code like this below:

~~~shell
# used by outside to build toolchain only
# the branch you want to use, eg. nuclei/2025
# For nuclei engineer, you can change the url to nuclei internal gito server url
# you can change the https url to ssh url, if you have setup ssh keys of github/gitee/gito
git clone -b nuclei/2025 --depth 1 https://github.com/riscv-mcu/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
# clone and update submodule
# FORCE_SUBMODULE=0: if you have already clone the correct branch and prepared submodule source code
# FORCE_SUBMODULE=1: if you have not clone submodule source code, or want to force update it, may fail, you need to debug it by yourself
# libncrt branch set to develop
# NOTICE: qemu repo's submodule is not init and updated, you need to handle it by yourself, it heavily depended on github network connection
FORCE_SUBMODULE=1 ./scripts/toolchain/prepsrc.sh develop
~~~

## Run docker image to build toolchain

We provide two docker images for build toolchains.

> [!NOTE]
> The following docker images are updated @ 2026.08.11

- [**gnutoolchain-centos7:v2**](https://hub.docker.com/r/nucleisoftware/gnutoolchain-centos7/tags): Used to build toolchain for linux 64 host (with Python 3.8.10 build environment installed).
- [**gnutoolchain-ubuntu20.04:v2**](https://hub.docker.com/r/nucleisoftware/gnutoolchain-ubuntu20.04/tags): Used to build toolchain for windows 32 and 64 host, windows 64 support is added from 2025.08, and Windows Python 3.8.10 cross-compilation support is added from 2026.08.

**Recommended**: You can use this ``docker.sh`` script to startup docker environment used to build toolchain.

~~~shell
# PULLFIRST=1 : pull the latest docker images first before run it to make sure the image locally is up to date, if set to 0, then will use local version if present.
# argment 1: toolchain host to be build for, win64, linux64 or win32, default is linux64
PULLFIRST=1 ./scripts/toolchain/docker.sh linux64
# The following commands are executed in docker image
# If you want to build win32/win64 toolchain, please make sure the same linux64 version is built first or use a prebuilt linux64 toolchain
# or you need to set PATH to include your linux toolchain path first.
# such as below:
# here are commands executed in docker environment, make sure the prebuilt toolchain are placed under LocalInstall folder
# for glibc: export PATH=/work/LocalInstall/linux64/glibc/2025.10/gcc/bin:$PATH
# for newlibc: export PATH=/work/LocalInstall/linux64/newlibc/2025.10/gcc/bin:$PATH
~~~

**Now you should be in docker environment now.**

Here assume we are build a **linux64** toolchain.

### Build toolchain

> [!WARNING]
> Now you should run in docker environment now

~~~shell
# cd to toolchain source root /work
cd /work
# Create you own build environment file based on scripts/toolchain/buildenv.sample template
cp scripts/toolchain/buildenv.sample mybuild.env
# Modify the environment variables in mybuild.env, see variable description in scripts/toolchain/build.sh
# No need to set TOOLHOST, it will be guessed by build.sh script
# Then use the build environment file like this
# Suggestion for normal development:
# you can set DOCLEAN=0 and DOCLEANPREFIX=1 : it will clean prebuilt toolchain for each fresh build and dont cleanup
# build folder for a successful build, then you can goto the build folder, and just go to selected build step folder
# to build and install such as gcc without a full rebuild -> just refer to the generated makefile steps
BUILDENV=mybuild.env source ./scripts/toolchain/setup_env.sh
# Now you can build toolchain now, and overwrite some variables during build like this
## eg. I want to change the toolchain version TOOLVER to 2025.08-test1, use 32 jobs
## And it will save build environment file to savebuild_<toolhost>_<tooltype>.env
TOOLVER=2025.08-test1 JOBS=32 ./scripts/toolchain/build.sh
# If DOCLEAN=1, then when toolchain is built successfully, the toolchain build folder will be cleanup,
# if you want to just build selected stages when small changes in source code, you should set DOCLEAN=0 to make sure build directory is not removed
# if failed, the build folder will not be cleaned, you can rebuilt it without reconfigure it by add DOREBUILD=1
DOREBUILD=1 TOOLVER=2025.08-test1 JOBS=32 ./scripts/toolchain/build.sh
# If toolchain build is failing you will get the toolchain build directory path in final log
# And you can also directly cd to the build folder, and cd to its subfolder to build one of stages
# eg. you can check the LocalBuilds/2025.08-test1_linux64_newlibc_20250804_035022/stamps folder to check which build stage
# is not finished, and cd to that stage folder and check whether configuring is failing or building is failing,
# and execute similar command as decribed in Makefile, eg. for stage build-gdb-newlib, just cd to build-gdb-newlib
# and execute make, and it will build gdb, if you want to install it, run make install
# make sure you have read the Makefile rule, now we are in AI Era, you can use AI to help you understand Makefile
# if you dont know Makefile, shell script, learn it, we dont provide any support for it
# you are a compiler engineer, this is basic skill you need to master
~~~

### Cleanup toolchain

> In docker environment now

You can cleanup build directories for specified tool version, tool host, tool type, and also clean installed
toolchain version.

~~~shell
# If you want to clean up installed local toolchain version please pass export CLEANINSTALL=1
# eg. cleanup tool version 2025.08-test1 linux64 newlibc
TOOLVER=2025.08-test1 TOOLHOST=linux64 TOOLTYPE=newlibc ./scripts/toolchain/cleanup.sh
~~~

## Release toolchain

> In host environment now, only for Nuclei internal usage

If you want to sync successfully built toolchain to internal share location, you can run it like this.

~~~shell
# Assume you want to sync tool version 2025.08-test1 linux64 newlibc
TOOLVER=2025.08-test1 TOOLHOST=linux64 TOOLTYPE=newlibc ./scripts/toolchain/release.sh
~~~

## FAQ

1. If compiling is failing unexpectedly, please check whether required gcc third party libraries are downloaded, and required gdb third party library is linked to gcc folder.

see example structure as below:

~~~
# sample output for downloading gcc prerequisites
INFO: Download gcc prerequisites...
2025-08-04 07:23:04 URL:https://gcc.gnu.org/pub/gcc/infrastructure/gettext-0.22.tar.gz [26105696/26105696] -> "gettext-0.22.tar.gz" [1]
2025-08-04 07:23:09 URL:https://gcc.gnu.org/pub/gcc/infrastructure/gmp-6.2.1.tar.bz2 [2493916/2493916] -> "gmp-6.2.1.tar.bz2" [1]
2025-08-04 07:23:13 URL:https://gcc.gnu.org/pub/gcc/infrastructure/mpfr-4.1.0.tar.bz2 [1747243/1747243] -> "mpfr-4.1.0.tar.bz2" [1]
2025-08-04 07:23:19 URL:https://gcc.gnu.org/pub/gcc/infrastructure/mpc-1.2.1.tar.gz [838731/838731] -> "mpc-1.2.1.tar.gz" [1]
2025-08-04 07:23:24 URL:https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.24.tar.bz2 [2261594/2261594] -> "isl-0.24.tar.bz2" [1]
gettext-0.22.tar.gz: OK
gmp-6.2.1.tar.bz2: OK
mpfr-4.1.0.tar.bz2: OK
mpc-1.2.1.tar.gz: OK
isl-0.24.tar.bz2: OK
All prerequisites downloaded successfully.
# sample output when build toolchain on branch nuclei/2025 for gcc 14.2 and gdb 16.2
riscv-gnu-toolchain/gcc $ git clean -fdx --dry-run
Would remove gettext
Would remove gettext-0.22.tar.gz
Would remove gettext-0.22/
Would remove gmp
Would remove gmp-6.2.1.tar.bz2
Would remove gmp-6.2.1/
Would remove isl
Would remove isl-0.24.tar.bz2
Would remove isl-0.24/
Would remove mpc
Would remove mpc-1.2.1.tar.gz
Would remove mpc-1.2.1/
Would remove mpfr
Would remove mpfr-4.1.0.tar.bz2
Would remove mpfr-4.1.0/
riscv-gnu-toolchain/gcc $ cd ../gdb
riscv-gnu-toolchain/gdb $ git clean -fdx --dry-run
Would remove gmp
Would remove isl
Would remove mpfr
riscv-gnu-toolchain/gdb $ ls -l mpfr gmp isl
lrwxrwxrwx 1 hqfang hqfang 10 Aug  6 11:45 gmp -> ../gcc/gmp/
lrwxrwxrwx 1 hqfang hqfang 10 Aug  6 11:45 isl -> ../gcc/isl/
lrwxrwxrwx 1 hqfang hqfang 11 Aug  6 11:45 mpfr -> ../gcc/mpfr/
~~~

You can try to rebuild the toolchain again.

2. Clean the prebuilt toolchain folder via `DOCLEANPREFIX` variable.

Sometimes toolchain build will fail due to prebuilt toolchain folder is not removed,
you can change the build environment file eg `mybuild.env`'s `DOCLEANPREFIX` from 0 to 1, and
then setup the toolchain environment again to make sure the prebuilt toolchain is removed.

example log output as below:

~~~
WARN: Create local build folder /work/LocalBuilds/2024.08_linux64_glibc_20240813_063601 for toolchain build
INFO: Remove existing install folder for toolchain
WARN: Create local install folder for toolchain installation
INFO: Enable llvm build
~~~
