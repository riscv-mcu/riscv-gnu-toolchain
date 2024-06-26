# How to build riscv toolchain for Nuclei RISC-V Processor

> [!NOTE]
>
> Build a releasable toolchain is a complicated thing, we just shared our script used internally here,> and we don't provide technical support for this script, you should look into the scripts by yourself to understand how it works.

This directory contains scripts required for building riscv toolchain
of Nuclei RISC-V processor.

The toolchain prefix is named `riscv64-unknown-elf-` for newlibc toolchain,
and `riscv64-unknown-linux-gnu-` for glibc toolchain now, which is
incompatiable with previous 2022.12 or earlier version of Nuclei
riscv toolchain name `riscv-nuclei-elf` for newlibc and `riscv-nuclei-linux-gnu-`
for glibc.

## Support Host and Requirements

- Tested on Ubuntu 20.04 Host, real machine not docker environment
- Git, docker or podman is required
- Good network connection to github, since most source code are pulled from there

## Directory contents

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

> We don't provide any support for these scripts, the best way to use it is to take a look at the script itself.

If you want to build this toolchain, you can clone source code like this below:

~~~shell
# used by outside to build toolchain only
# the branch to be build, select nuclei/2024-gcc13
# For nuclei engineer, you can change the url to nuclei internal gito server url
# you can change the https url to ssh url, if you have setup ssh keys of github/gitee/gito
git clone -b nuclei/2024-gcc13 --depth 1 https://github.com/riscv-mcu/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
# clone and update submodule
# FORCE_SUBMODULE=0: if you have already clone the correct branch and prepared submodule source code
# FORCE_SUBMODULE=1: if you have not clone submodule source code, or want to force update it, may fail, you need to debug it by yourself
# libncrt branch set to feature/rvgcc
# NOTICE: qemu repo's submodule is not init and updated, you need to handle it by yourself, it heavily depended on github network connection
FORCE_SUBMODULE=1 ./scripts/toolchain/prepsrc.sh feature/rvgcc
~~~

## Run docker image to build toolchain

> [!WARNING]
> In host environment now

We provide two docker images for build toolchains.

- **gnutoolchain-centos6**: Used to build toolchain for linux host.
- **gnutoolchain-ubuntu18.04**: Used to build toolchain for windows host.

You can use this docker.sh script to startup docker environment used to build toolchain.

~~~shell
# PULLFIRST=1 : pull the latest docker images first before run it to make sure the image locally is up to date, if set to 0, then will use local version if present.
# argment 1: toolchain host to be build for, linux64 or win32, default is linux64
PULLFIRST=1 ./scripts/toolchain/docker.sh linux64

# If you want to build win32 toolchain, please make sure the same linx64 version is built first
# or you need to set PATH to include your linux toolchain path first.
# such as below:
# for glibc: export PATH=/work/LocalInstall/linux64/glibc/2024.07-eng1/gcc/bin:$PATH
# for newlibc: export PATH=/work/LocalInstall/linux64/newlibc/2024.07-eng1/gcc/bin:$PATH
~~~

Now you should be in docker environment now.

Here assume we are build a linux64 toolchain.

### Build toolchain

> [!WARNING]
> In docker environment now

~~~shell
# cd to toolchain source root /work
cd /work
# Create you own build environment file based on scripts/toolchain/buildenv.sample template
cp scripts/toolchain/buildenv.sample mybuild.env
# Modify the environment variables in mybuild.env, see variable description in scripts/toolchain/build.sh
# No need to set TOOLHOST, it will be guessed by build.sh script
# Then use the build environment file like this
BUILDENV=mybuild.env source ./scripts/toolchain/setup_env.sh
# Now you can build toolchain now, and overwrite some variables during build like this
## eg. I want to change the toolchain version TOOLVER to 2024.07-test1, use 32 jobs
## And it will save build environment file to savebuild_<toolhost>_<tooltype>.env
TOOLVER=2024.07-test1 JOBS=32 ./scripts/toolchain/build.sh
# If DOCLEAN=1, then when toolchain is built successfully, the toolchain build folder will be cleanup,
# if failed, the build folder will not be cleaned, you can rebuilt it without reconfigure it by add DOREBUILD=1
DOREBUILD=1 TOOLVER=2024.07-test1 JOBS=32 ./scripts/toolchain/build.sh
# If you don't want to rebuild all this repo, you just want to build one of the repo
# you can also directly cd to the build folder, and cd to its subfolder to build one of stages
# The build folder will be displayed in the console, please take care, you can refer $toolbuilddir in the scripts/toolchain/build.sh
# to see how it works and you also need to refer to the Makefile.in to see what commands are really executed during each step
~~~

### Cleanup toolchain

> [!WARNING]
> In docker environment now

You can cleanup build directories for specified tool version, tool host, tool type, and also clean installed
toolchain version.

~~~shell
# If you want to clean up installed local toolchain version please pass export CLEANINSTALL=1
# eg. cleanup tool version 2024.07-eng1 linux64 newlibc
TOOLVER=2024.07-eng1 TOOLHOST=linux64 TOOLTYPE=newlibc ./scripts/toolchain/cleanup.sh
~~~

## Release toolchain

> [!WARNING]
> In host environment now, only for Nuclei internal usage

If you want to sync successfully built toolchain to internal share location, you can run it like this.

~~~shell
# Assume you want to sync tool version 2024.07-eng1 linux64 newlibc
TOOLVER=2024.07-eng1 TOOLHOST=linux64 TOOLTYPE=newlibc ./scripts/toolchain/release.sh
~~~
