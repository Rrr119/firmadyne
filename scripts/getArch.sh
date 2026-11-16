#!/bin/bash

# Note: the helper functions below are intentionally defined before any
# `set -e`/`set -u`, so that this script may also be sourced by the test
# suite (e.g. tests/test_getArch.sh) without aborting on unbound variables.

# Supported emulation targets. Keep in sync with ARCHS in firmadyne.config.
SUPPORTED_ARCHES="armel arm64el mipseb mipsel mips64eb mips64el intelel intel64el"

# Map the output of `file` to a (potentially endian-less) architecture name.
# Order matters: the 64-bit ARM and MIPS patterns must be tested before the
# 32-bit ones, otherwise e.g. "ELF 64-bit LSB ... ARM aarch64" is misdetected
# as plain 32-bit ARM.
function getArch() {
    if (echo ${FILETYPE} | grep -qE "MIPS64|N64")
    then
        ARCH="mips64"
    elif (echo ${FILETYPE} | grep -q "MIPS")
    then
        ARCH="mips"
    elif (echo ${FILETYPE} | grep -qE "ARM64|aarch64")
    then
        ARCH="arm64"
    elif (echo ${FILETYPE} | grep -q "ARM")
    then
        ARCH="arm"
    elif (echo ${FILETYPE} | grep -q "x86-64")
    then
        ARCH="intel64"
    elif (echo ${FILETYPE} | grep -q "Intel 80386")
    then
        ARCH="intel"
    elif (echo ${FILETYPE} | grep -q "64-bit PowerPC")
    then
        ARCH="ppc64"
    elif (echo ${FILETYPE} | grep -q "PowerPC")
    then
        ARCH="ppc"
    else
        ARCH=""
    fi
}

function getEndian() {
    if (echo ${FILETYPE} | grep -q "LSB")
    then
        END="el"
    elif (echo ${FILETYPE} | grep -q "MSB")
    then
        END="eb"
    else
        END=""
    fi
}

# Architectures that only ever use a single byte order. The endianness suffix
# is still appended so every target has a uniform "<arch><end>" identifier.
function defaultEndian() {
    case "${1}" in
        arm|arm64|intel|intel64)
            echo "el"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Best-effort extraction of a kernel version (e.g. "3.4.11-rt19") from the
# output of `file` against a Linux kernel image. Returns an empty string when
# no version can be determined.
function getKernelVersion() {
    local version
    version=$(echo "${FILETYPE}" | grep -oiE "version [0-9]+\.[0-9]+[0-9a-zA-Z._~+-]*" \
        | head -n 1 | sed -E "s/^[Vv]ersion //")
    if [ -z "${version}" ]
    then
        version=$(echo "${FILETYPE}" | grep -oE "Linux kernel.*[0-9]+\.[0-9]+[0-9a-zA-Z._~+-]*" \
            | grep -oE "[0-9]+\.[0-9]+[0-9a-zA-Z._~+-]*" | head -n 1)
    fi
    echo "${version}"
}

function isSupportedArchEnd() {
    for supported in ${SUPPORTED_ARCHES}
    do
        if [ "${1}" == "${supported}" ]
        then
            return 0
        fi
    done
    return 1
}

if [ "${0##*/}" == "getArch.sh" ]
then
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

INFILE=${1}
BASE=$(basename "$1")
IID=${BASE%.tar.gz}

mkdir -p "/tmp/${IID}"

set +e
FILES="$(tar -tf $INFILE | grep -e "/busybox\$") "
FILES+="$(tar -tf $INFILE | grep -E "/sbin/[[:alpha:]]+")"
FILES+="$(tar -tf $INFILE | grep -E "/bin/[[:alpha:]]+")"
set -e

for TARGET in ${FILES}
do
    SKIP=$(echo "${TARGET}" | grep -F -o / | wc -l)
    tar -xf "${INFILE}" -C "/tmp/${IID}/" --strip-components=${SKIP} ${TARGET}
    TARGETLOC="/tmp/$IID/${TARGET##*/}"

    if [ -h ${TARGETLOC} ] || [ ! -f ${TARGETLOC} ]
    then
        continue
    fi

    FILETYPE=$(file ${TARGETLOC})

    echo -n "${TARGET}: "
    getArch
    getEndian

    # Normalise the endianness for fixed-endian architectures whose `file`
    # output does not contain an LSB/MSB marker.
    if [ -z "${END}" ]
    then
        END=$(defaultEndian "${ARCH}")
    fi

    if [ -n "${ARCH}" ] && [ -n "${END}" ]
    then
        ARCHEND=${ARCH}${END}
        KERNEL_VERSION=$(getKernelVersion)

        if isSupportedArchEnd "${ARCHEND}"
        then
            echo "${ARCHEND}"
        else
            # e.g. armeb/ppcel/ppceb: recognised, but no QEMU support yet.
            echo "${ARCHEND} (detected, but emulation is not supported)"
            psql -d firmware -U firmadyne -h 127.0.0.1 -q -c "UPDATE image SET arch = '$ARCHEND' WHERE id = $IID;"
            [ -n "${KERNEL_VERSION}" ] && psql -d firmware -U firmadyne -h 127.0.0.1 -q -c "UPDATE image SET kernel_version = '$KERNEL_VERSION' WHERE id = $IID;"
            rm -fr "/tmp/${IID}"
            exit 2
        fi

        if [ -n "${KERNEL_VERSION}" ]
        then
            echo "${ARCHEND} (kernel ${KERNEL_VERSION})"
            psql -d firmware -U firmadyne -h 127.0.0.1 -q -c "UPDATE image SET arch = '$ARCHEND', kernel_version = '$KERNEL_VERSION' WHERE id = $IID;"
        else
            psql -d firmware -U firmadyne -h 127.0.0.1 -q -c "UPDATE image SET arch = '$ARCHEND' WHERE id = $IID;"
        fi

        rm -fr "/tmp/${IID}"
        exit 0
    else
        echo -n ${ARCH}
        echo ${END}
    fi
done

rm -fr "/tmp/${IID}"

exit 1
fi
