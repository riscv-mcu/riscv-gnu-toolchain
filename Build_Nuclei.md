# Build RISC-V GNU Toolchain For Nuclei

[![Build Nuclei GNU Toolchain](https://github.com/riscv-mcu/riscv-gnu-toolchain/workflows/Build%20GNU%20Toolchain/badge.svg)](https://github.com/riscv-mcu/riscv-gnu-toolchain/actions)

This guide is used to provide steps for build windows and linux version of **RISC-V GNU Toolchain for Nuclei**.

## Get toolchain sources

This repository uses submodules. You need the `--recursive` option to fetch the submodules automatically.

The Nuclei maintained source code is located in **nuclei-multilib** branch, please use this branch.

~~~
cd ~
git clone https://github.com/riscv-mcu/riscv-gnu-toolchain
git checkout nuclei-multilib
git submodule update --init --recursive
~~~

## Install prerequisites

To build windows or linux version, you need to choose a proper version of linux distribution, here we recommend to use **Ubuntu 16.04 64bit** version, you can use docker tool to easily get this version if you already have installed Ubuntu.

You also need to install extra packages to build toolchain:

* To build linux toolchain, you need to install following packages using this command below:

  ~~~shell
  sudo apt-get install autoconf automake autotools-dev bc bison \
       build-essential curl dejagnu expect flex gawk gperf libtool patchutils texinfo
  ~~~

* To build windows toolchain, you need to install following packages using this command below:

  ~~~shell
  sudo apt-get install autoconf automake autotools-dev bc bison \
      build-essential curl dejagnu expect flex gawk gperf \
      libtool patchutils texinfo python3 zip \
      mingw-w64 gdb-mingw-w64 libz-mingw-w64-dev
  ~~~
  
For windows build, you also need to build `libexpat` using command below:
  
~~~shell
  wget https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2
  tar -xjf expat-2.2.9.tar.bz2
  cd expat-2.2.9
  ./configure --host=i686-w64-mingw32 --prefix=/usr/i686-w64-mingw32/
  make -j4
  sudo make install
  ~~~
  
And then remove `zlib1.dll` and `libexpat-1.dll` using commands below(**execute using sudo**):
  
~~~shell
  for i in `find /usr/i686-w64-mingw32/ -name "*.dll"`; do sudo mv $i $i.bak;  done
  [ -f /usr/x86_64-w64-mingw32/lib/zlib1.dll ] && sudo mv /usr/x86_64-w64-mingw32/lib/zlib1.dll /usr/x86_64-w64-mingw32/lib/zlib1.dll.bak
  [ -f /usr/i686-w64-mingw32/lib/libexpat.dll.a ] && sudo mv /usr/i686-w64-mingw32/lib/libexpat.dll.a /usr/i686-w64-mingw32/lib/libexpat.dll.a.bak
  [ -f /usr/i686-w64-mingw32/lib/libz.dll.a ] && sudo mv /usr/i686-w64-mingw32/lib/libz.dll.a /usr/i686-w64-mingw32/lib/libz.dll.a.bak
  [ -f /usr/x86_64-w64-mingw32/lib/libz.dll.a ] && sudo mv /usr/x86_64-w64-mingw32/lib/libz.dll.a /usr/x86_64-w64-mingw32/lib/libz.dll.a.bak
  ~~~

## Build Linux Toolchain

**Make sure you have installed the required prerequisites and downloaded toolchain source code before build toolchain.**

Assumed your toolchain source code located in `~/riscv-gnu-toolchain`, and you want to build toolchain to `$HOME/riscv_lin`.

1. You can execute the following commands to build for **linux baremetal/newlib** toolchain:

   ~~~shell
   cd ~/riscv-gnu-toolchain
   export PREFIX=${HOME}/riscv_lin
   # Configure linux newlibc x64 build and enable multilib
   ./configure --with-arch=rv32gc --enable-multilib --prefix=$PREFIX --with-cmodel=medany
   # Download extra prerequisites(GMP, MPFR and MPC libraries)
   # see https://gcc.gnu.org/install/download.html
   cd ./riscv-gcc/ && ./contrib/download_prerequisites
   cd -
   # change toolchain name to nuclei
   sed -i -e 's/make_tuple = riscv$(1)-unknown-$(2)/make_tuple = riscv-nuclei-$(2)/g' Makefile
   # If you want to build faster, you can change -j4 to -j
   export MAKE="make -j4"
   # Build toolchain, may cost about 1 hour depend on your machine
   make
   ~~~

2. You can strip unused symbols to downsize the binaries using commands below if toolchain is built successfully, and tar the toolchain to `nuclei_gcc_lin64.tar.bz2`:

   ~~~shell
   cd $PREFIX
   set +e
   # Strip unused symbols in toolchain binaries
   for i in `find libexec bin -type f`; do strip -s $i ; done
   cd ..
   # archive the toolchain
   tar -jcf nuclei_gcc_lin64.tar.bz2 riscv_lin
   ~~~
   
3. Then you can use this toolchain in linux 64bit environment with your riscv software.

If you want to check for sample build log, you can check our successful github ci build, such as https://github.com/riscv-mcu/riscv-gnu-toolchain/runs/1315017585

If you want to build for **linux glibc toolchain**, you can replace the **step 1** above with commands below, toolchain installed to `$HOME/riscv_glibc_lin`:

~~~shell
cd ~/riscv-gnu-toolchain
export PREFIX=${HOME}/riscv_glibc_lin
# Configure linux glibc x64 build and enable multilib
./configure --prefix=$PREFIX --with-arch=rv64gc --with-abi=lp64d --enable-multilib --with-cmodel=medany
# Download extra prerequisites(GMP, MPFR and MPC libraries)
# see https://gcc.gnu.org/install/download.html
cd ./riscv-gcc/ && ./contrib/download_prerequisites
cd -
# change toolchain name to nuclei
sed -i -e 's/make_tuple = riscv$(1)-unknown-$(2)/make_tuple = riscv-nuclei-$(2)/g' Makefile
# If you want to build faster, you can change -j4 to -j
export MAKE="make -j4"
# Build toolchain, may cost about 1 hour depend on your machine
make linux
~~~

## Build Windows Toolchain

**Make sure you have installed the required prerequisites and downloaded toolchain source code before building toolchain.**

**You already build nuclei riscv toolchain for linux, and installed it into `$HOME/riscv_lin`.**

Assumed your toolchain source code located in `~/riscv-gnu-toolchain`, and you want to build toolchain to `$HOME/riscv_win`.

1. Export riscv nuclei linux toolchain to path to build newlib library for **windows baremetal/newlib** toolchain.

    ~~~shell
    export PATH=$HOME/riscv_lin/bin:$PATH
    ~~~
    
2. You can execute the following commands to build for windows toolchain:

    ~~~shell
    cd ~/riscv-gnu-toolchain
    export PREFIX=${HOME}/riscv_win
    # Configure w32 newlibc build and enable multilib
    ./configure --with-arch=rv32gc --enable-multilib --prefix=$PREFIX --with-host=i686-w64-mingw32 --with-cmodel=medany
    # Download extra prerequisites(GMP, MPFR and MPC libraries)
    # see https://gcc.gnu.org/install/download.html
    cd ./riscv-gcc/ && ./contrib/download_prerequisites
    cd -
    # change toolchain name to nuclei
    sed -i -e 's/make_tuple = riscv$(1)-unknown-$(2)/make_tuple = riscv-nuclei-$(2)/g' Makefile
    # If you want to build faster, you can change -j4 to -j
    export MAKE="make -j4"
    # Build toolchain, may cost about 1 hour depend on your machine
    make
    ~~~

2. You can strip unused symbols to downsize the binaries using commands below if toolchain is built successfully, and zip the toolchain to `nuclei_gcc_win32.zip`:

   ~~~shell
   cd $PREFIX
   # Strip unused symbols in toolchain binaries
   for i in `find . -name *.dll`; do i686-w64-mingw32-strip -s $i ; done
   for i in `find . -name *.exe`; do i686-w64-mingw32-strip -s $i ; done
   cd ..
   # zip the toolchain
   zip -r -9 nuclei_gcc_win32.zip riscv_win
   ~~~
   
3. Then you can use this toolchain in windows with your riscv software.

If you want to check for sample build log, you can check our successful github ci build, such as https://github.com/riscv-mcu/riscv-gnu-toolchain/runs/1315673828
