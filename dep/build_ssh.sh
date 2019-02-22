#!/bin/bash
set -e

unset CFLAGS
unset CPPFLAGS
unset LDFLAGS

INST_PREFIX=${INST_PREFIX:-/opt/udiImage}
SPRT_PREFIX=$( mktemp -d )
PREFIX=$( mktemp -d )
MUSL_VERSION=1.1.21
LIBRESSL_VERSION=2.8.3
ZLIB_VERSION=1.2.11
DROPBEAR_VERSION=2018.76

origdir=$( pwd )
mkdir -p build
cd build
builddir=$( pwd )

if [[ -z "$INST_PREFIX" || "$INST_PREFIX" == "/" ]]; then
    echo "Invalid installation target: $INST_PREFIX" 1>&2
    exit 1
fi

if [[ ! -e "musl-${MUSL_VERSION}.tar.gz" && -n "$DEPTAR_DIR" && -e "$DEPTAR_DIR/musl-${MUSL_VERSION}.tar.gz" ]]; then
    cp "$DEPTAR_DIR/musl-${MUSL_VERSION}.tar.gz" .
fi
if [[ ! -e "musl-${MUSL_VERSION}.tar.gz" ]]; then
    curl -o "musl-${MUSL_VERSION}.tar.gz" "http://www.musl-libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
fi
if [[ ! -e "libressl-${LIBRESSL_VERSION}.tar.gz" && -n "$DEPTAR_DIR" && -e "$DEPTAR_DIR/libressl-${LIBRESSL_VERSION}.tar.gz" ]]; then
    cp "$DEPTAR_DIR/libressl-${LIBRESSL_VERSION}.tar.gz" .
fi
if [[ ! -e "libressl-${LIBRESSL_VERSION}.tar.gz" ]]; then
    curl -o "libressl-${LIBRESSL_VERSION}.tar.gz" "http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VERSION}.tar.gz"
fi
if [[ ! -e "zlib-${ZLIB_VERSION}.tar.gz" && -n "$DEPTAR_DIR" && -e "$DEPTAR_DIR/zlib-${ZLIB_VERSION}.tar.gz" ]]; then
    cp "$DEPTAR_DIR/zlib-${ZLIB_VERSION}.tar.gz" .
fi
if [[ ! -e "zlib-${ZLIB_VERSION}.tar.gz" ]]; then
    curl -o "zlib-${ZLIB_VERSION}.tar.gz" "http://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz"
fi
if [[ ! -e "dropbear-${DROPBEAR_VERSION}.tar.bz2" && -n "$DEPTAR_DIR" && -e "$DEPTAR_DIR/dropbear-${DROPBEAR_VERSION}.tar.bz2" ]]; then
    cp "$DEPTAR_DIR/dropbear-${DROPBEAR_VERSION}.tar.bz2" .
fi
if [[ ! -e "dropbear-${DROPBEAR_VERSION}.tar.bz2" ]]; then
    curl -o "dropbear-${DROPBEAR_VERSION}.tar.bz2" "https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
fi

mkdir -p musl
tar xf "musl-${MUSL_VERSION}.tar.gz" -C musl --strip-components=1
cd musl
./configure "--prefix=${SPRT_PREFIX}" --enable-static --disable-shared --enable-gcc-wrapper
make
make install
cd "${builddir}"

dirs="linux asm asm-generic x86_64-linux-gnu/asm"
for dir in $dirs; do
    if [[ -e "/usr/include/$dir" ]]; then
        if [[ -L "/usr/include/$dir" ]]; then
            # SLES has symlinks for asm
            realpath=$(readlink -f "/usr/include/$dir")
            cp -rp "$realpath" "${SPRT_PREFIX}/include/"
        fi
        cp -rp "/usr/include/$dir" "${SPRT_PREFIX}/include/"
    fi
done

cd "${builddir}"
mkdir -p libressl
tar xf "libressl-${LIBRESSL_VERSION}.tar.gz" -C libressl --strip-components=1
cd libressl
CC="${SPRT_PREFIX}/bin/musl-gcc" ./configure "--prefix=${SPRT_PREFIX}" --enable-static --disable-shared --host=$(uname -m)
make
make install

cd "${builddir}"
mkdir -p zlib
tar xf "zlib-${ZLIB_VERSION}.tar.gz" -C zlib --strip-components=1
cd zlib
CC="${SPRT_PREFIX}/bin/musl-gcc" ./configure "--prefix=${SPRT_PREFIX}"
make
make install

cd "${builddir}"
mkdir -p dropbear
tar xjf "dropbear-${DROPBEAR_VERSION}.tar.bz2" -C dropbear --strip-components=1
cd dropbear

## it is important to change PATH here so that the default PATH when ssh'd into
## the image is not infected with all kinds of silly paths (sshd sets PATH to
## very nearly the path it was built with)
export PATH="/usr/bin:/bin"
LDFLAGS="-L${SPRT_PREFIX}/lib -L${SPRT_PREFIX}/lib64" CC="${SPRT_PREFIX}/bin/musl-gcc" ./configure --without-pam "--with-ssl-dir=${SPRT_PREFIX}" --enable-static --with-zlib="${SPRT_PREFIX}" --prefix="${INST_PREFIX}" --host=$(uname -m)
make
make install "DESTDIR=${PREFIX}"

cd "${PREFIX}"
tar cf "${origdir}/udiRoot_dep.tar" .
cd "${origdir}"
rm -r "${PREFIX}"
rm -r "${SPRT_PREFIX}"
