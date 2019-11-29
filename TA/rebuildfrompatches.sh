#!/bin/bash

# prepare workdirs
TMPDIR=$(mktemp -d)
CURDIR=$(pwd)

# get upstream
wget https://github.com/linaro-swg/optee_examples/archive/3.7.0.tar.gz -O - | tar -C ${TMPDIR} -xz --wildcards \*/hello_world/\* --strip=2

cd ${TMPDIR}
patch -p2 -i ${CURDIR}/01*
patch -p1 -i ${CURDIR}/02*

echo "your code is in ${TMPDIR}"