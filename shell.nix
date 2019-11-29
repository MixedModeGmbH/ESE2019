# \file shell.nix
# \brief set up a nix-shell for Development with OP-TEE
# \usage in the folder containing this file call 'nix-shell --pure'
#
# Assuming an installen Nix package manager (Version > 2.0), this file can
# be used to load a reproducible development environment for OP-TEE.
# The derivation loads all required dependencies to build a full ecosystem
# for developing with OP-TEE using Buildroot and QEMU.
# This includes the initial build of all software at first launch.
# 
#
# \copyright Copyright (c) 2019 Mixed Mode GmbH.
# SPDX-License-Identifier: CC-BY-NC-SA-4.0

let
  fetchNixpkgs = import ./fetchNixpkgs.nix;
  rev = "c75de8bc12cc7e713206199e5ca30b224e295041"; # 19.09 as of 30-oct-2019
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
    sha256 = "1awipcjfvs354spzj2la1nzmi9rh2ci2mdapzf4kkabf58ilra6x"; # 19.09 as of 30-oct-2019
  };

in
with import nixpkgs { config = {}; overlays = []; };

let
  # provide the old, unsafe pycrypto due to compatibility issues with cryptodome
  # see also https://raw.githubusercontent.com/mayflower/nixpkgs/master/pkgs/development/python-modules/pycrypto-original/default.nix
  pycrypto-original = python37.pkgs.buildPythonPackage rec {
    pname = "pycrypto-original";
    version = "2.6.1";
    src = python37.pkgs.fetchPypi {
      inherit pname version;
      sha256 = "0g0ayql5b9mkjam8hym6zyg6bv77lbh66rv1fyvgqb17kfc1xkpj";
    };
  
    patches = [
      (fetchpatch {
        name = "CVE-2013-7459.patch";
        url = "https://anonscm.debian.org/cgit/collab-maint/python-crypto.git/plain/debian/patches/CVE-2013-7459.patch?h=debian/2.6.1-7";
        sha256 = "01r7aghnchc1bpxgdv58qyi2085gh34bxini973xhy3ks7fq3ir9";
      })
    ];
  
    preConfigure = ''
      sed -i 's,/usr/include,/no-such-dir,' configure
      sed -i "s!,'/usr/include/'!!" setup.py
    '';
  
    buildInputs = stdenv.lib.optional (!python.isPypy or false) gmp; # optional for pypy
  
    doCheck = !(python.isPypy or stdenv.isDarwin); # error: AF_UNIX path too long
  
    meta = {
      homepage = "http://www.pycrypto.org/";
      description = "Python Cryptography Toolkit";
      platforms = stdenv.lib.platforms.unix;
    };
  };
in
pkgs.mkShell {
  name = "op-tee-on-qemu";

  nativeBuildInputs = [ 
    # pull in build-requirements
    androidenv.androidPkgs_9_0.platform-tools
    autoconf
    automake
    bc
    bison
    cacert
    cpio
    cscope 
    curl
    dtc
    expect
    flex
    gcc 
    git
    gitRepo
    gnumake
    gnutar 
    gptfdisk
    hostname 
    iasl
    libtool
    m4
    mtools
    netcat
    perl
    pkgconfig
    pycrypto-original # *sigh*, see above
    python37Packages.pyelftools
    python37Packages.pyserial
    python37Packages.Wand
    rsync
    unzip
    wget
    which
    xdg_utils
    xterm
    xz
    
    # and some useful additions
    ccache
    coreutils
    ninja
    screen
  ];

  # required libs for linking
  buildInputs = [
    attr
    db
    gdbm
    glib
    glibc
    glibc_multi
    gmp
    hidapi
    libcap
    libuuid
    linuxHeaders
    ncurses
    ncurses5
    openssl
    pixman
    readline70
    zlib
  ];

  # building requires some relaxing on hardening options
  # this is fine for a playground QEMU/Buildroot

  hardeningDisable = [ "fortify" "format" ];

  # this shell hook will set up the environment, pre-build everything once and
  # set semaphores to avoid restarting the builds
  # TODO: make a derivation for the initial build and just copy over everything
  # that does not exist when the shell hook is executed
  shellHook = ''
    PROMPT_COMMAND='PS1="nix-shell@OP-TEE Test| \W>";'

    # we need to allow linking against some build results
    NIX_ENFORCE_PURITY=0

    # and we need to slightly modify the search paths to avoid '#include_next' uglinesses
    echo $NIX_CFLAGS_COMPILE > nix_cflags_compile.tmp
    perl -pi -e 's/([^\\])( -isystem)/$1\n$2/g' nix_cflags_compile.tmp # one per line
    sed -i '/-glibc-2/d' nix_cflags_compile.tmp # drop -isystem glibc
    grep -m1 '.-linux-headers-' nix_cflags_compile.tmp | perl -p -e 's/([^\\] -i)system/$1dirafter/g' >> nix_cflags_compile.tmp # for buildroot's host-zlib
    grep -m1 '.-readline-7' nix_cflags_compile.tmp | perl -p -e 's/([^\\] -i)system/$1dirafter/g' >> nix_cflags_compile.tmp # for buildroot's host-fdisk
    NIX_GLIBC_HEADERS=$(grep -m1 '.-glibc-' nix_cflags_compile.tmp | perl -p -e 's/([^\\] -i)system/$1dirafter/g')
    perl -pi -e 's/\R//g' nix_cflags_compile.tmp # all back on one line
    NIX_CFLAGS_COMPILE=$(<nix_cflags_compile.tmp)
    
    # prepare source
    if [ ! -d "./optee-qemu" ]; then
      mkdir -p ./optee-qemu
    fi  
    cd optee-qemu 

    # get source and patch
    if [ ! -d "./.repo" ]; then
      repo init -u https://github.com/OP-TEE/manifest.git -m default.xml -b 3.6.0
    fi  
    if [ ! -f ".initial-sync.done" ]; then
      repo sync && touch .initial-sync.done
      sed -i 's+^#!/usr/bin/env python$+#!/usr/bin/env python3+' ./optee_os/scripts/sign.py
      # add missing flag for Buildroot's Host-Python (there is no NIX_LDLIBS and LDLIBS is not passed properly is it?)
      # do not set globally, as this would break the build of QEMU
      sed -i 's!@(cd .. && python build/br-ext/scripts/make_def_config.py!@export NIX_CFLAGS_COMPILE="$(NIX_CFLAGS_COMPILE) -lcrypt"; (cd .. \&\& python build/br-ext/scripts/make_def_config.py!' ./build/common.mk
      sed -i 's!@$(MAKE) -C ../out-br all!@export NIX_CFLAGS_COMPILE="$(NIX_CFLAGS_COMPILE) -lcrypt"; $(MAKE) -C ../out-br all!' ./build/common.mk

      # fix optee_test.mk: long PATH times 18 test cases overflows execvp, so push enumeration down the call stack
      wget -O ./build/br-ext/package/optee_test/optee_test.mk https://raw.githubusercontent.com/OP-TEE/build/ca60a6bc9b060ea1b567301e533c0ca917b3b76b/br-ext/package/optee_test/optee_test.mk
      wget -O ./build/br-ext/package/optee_examples/optee_examples.mk https://raw.githubusercontent.com/OP-TEE/build/ca60a6bc9b060ea1b567301e533c0ca917b3b76b/br-ext/package/optee_examples/optee_examples.mk
    fi  

    # load toolchains
    # TODO: this could be converted to a fixed-output derivation plus adding a few symlinks here
    if [ ! -f ".init-toolchain.done" ]; then
      cd build
      make toolchains -j 4 && touch ../.init-toolchain.done
      cd ..
    fi  

    # easily go back to a clean state without redownloading everything
    if [ ! -f ../snapshot.tar ]; then 
      cd ..
      tar -cf snapshot.tar optee-qemu
      cd optee-qemu
    fi  

    # enable file sharing between QEMU and the host
    if [ ! -d "./qemu-share" ]; then
      mkdir ./qemu-share
    fi  

    QEMU_VIRTFS_ENABLE=y
    QEMU_VIRTFS_HOST_DIR="$(pwd)/qemu-share"
    QEMU_USERNET_ENABLE=y

    # build QEMU and Buildroot once, without parallelism 
    # -> to avoid overloading system
    # -> and avoid race conditions (QEMU/Buildroot build can be brittle)

    WORKDIR_ALIAS=$(pwd)

    if [ ! -f ".initial-build.done" ]; then
      pushd "$WORKDIR_ALIAS/build" > /dev/null
      make -j1 all && touch ../.initial-build.done
      popd > /dev/null
    fi  

    alias runqemu='pushd "$WORKDIR_ALIAS/build" > /dev/null; \
       make -sj1 run-only QEMU_VIRTFS_ENABLE=y QEMU_VIRTFS_HOST_DIR="$QEMU_VIRTFS_HOST_DIR" QEMU_USERNET_ENABLE=y; \
       popd  > /dev/null'
    
    echo Welcome to your OP-TEE on QEMU playground.
    echo "Type 'runqemu<Enter>' to launch QEMU."
  '';
}
