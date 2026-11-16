#!/bin/bash

set -e
set -u

if [ -e ./firmadyne.config ]; then
    source ./firmadyne.config
elif [ -e ../firmadyne.config ]; then
    source ../firmadyne.config
else
    echo "Error: Could not find 'firmadyne.config'!"
    exit 1
fi

if check_number $1; then
    echo "Usage: run.mips64eb-debug.sh <image ID>"
    exit 1
fi
IID=${1}

WORK_DIR=`get_scratch ${IID}`
IMAGE=`get_fs ${IID}`
KERNEL=`get_kernel "mips64eb"`

qemu-system-mips64 -m 256 -M malta -kernel ${KERNEL} -drive if=ide,format=raw,file=${IMAGE} -append "firmadyne.syscall=0 root=/dev/sda1 console=ttyS0 nandsim.parts=64,64,64,64,64,64,64,64,64,64 rdinit=/firmadyne/preInit.sh rw debug ignore_loglevel print-fatal-signals=1" -nographic -netdev socket,id=s0,listen=:2000 -device e1000,netdev=s0 -netdev socket,id=s1,listen=:2001 -device e1000,netdev=s1 -netdev socket,id=s2,listen=:2002 -device e1000,netdev=s2 -netdev socket,id=s3,listen=:2003 -device e1000,netdev=s3
