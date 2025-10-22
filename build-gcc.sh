#! /bin/bash
# N64 MIPS GCC toolchain build/install script for Unix distributions
# originally based off libdragon's toolchain script,
# which was licensed under the Unlicense.
# (c) 2012-2021 DragonMinded and libDragon Contributors.

# modified by easyaspi314 to allow fscked toolchain setups

# Exit on error
set -e
set -x

INSTALL_PATH="$(pwd)/mips-n64-toolchain"

if ! mkdir -p "$INSTALL_PATH" || ! [ -w "$INSTALL_PATH" ]
then
    echo "Error accessing ${INSTALL_PATH}, perhaps try again with sudo?"
    exit 1
fi

echo "== Base ABI =="

ABI=32
GPRSIZE=32
MIPS="mips"
FP_FLAGS="--with-float=hard --with-fp-32=32 --with-fpu=double"
ABI_FLAGS="-mno-abicalls -fno-PIC -mgp32"
TARGET_FLAGS="${TARGET_FLAGS:--march=vr4300 -mtune=vr4300 -mfix4300}"
OPT_FLAGS="${OPT_FLAGS:--mno-check-zero-division -Os}"

# Set PATH for newlib to compile using GCC for MIPS N64 (pass 1)
export PATH="$PATH:$INSTALL_PATH/bin"

# Determine how many parallel Make jobs to run based on CPU count
JOBS="${JOBS:-`getconf _NPROCESSORS_ONLN`}"
JOBS="${JOBS:-1}" # If getconf returned nothing, default to 1

# Dependency source libs (Versions)
BINUTILS_V=2.30
GCC_V=12.2.0
NEWLIB_V=4.1.0

# MacOS has it's own z-lib that is not compatible with the build, so we need to set flags to use the SDK version
if [[ "$OSTYPE" == darwin* ]]; then
    ZLIB_FLAG="--with-system-zlib"
    MACOS_CFLAGS=""
    MACOS_CXXFLAGS=""
    MACOS_DISABLE_FLAGS=""
else
    ZLIB_FLAG=""
    MACOS_CFLAGS=""
    MACOS_CXXFLAGS=""
    MACOS_DISABLE_FLAGS=""
fi

# Check if a command-line tool is available: status 0 means "yes"; status 1 means "no"
command_exists () {
  (command -v "$1" >/dev/null 2>&1)
  return $?
}

# Download the file URL using wget or curl (depending on which is installed)
download () {
  if   command_exists aria2c ; then aria2c -c -s 16 -x 16 "$1"
  elif command_exists wget ; then wget -c  "$1"
  elif command_exists curl ; then curl -LO "$1"
  else
    echo "Install `wget` or `curl` or `aria2c` to download toolchain sources" 1>&2
    return 1
  fi
}

unzip_and_patch () {
  tar -xJf "$1.tar.xz"
  pushd $1
  patch -p1 < ../$2
  popd
}

# Dependency source: Download stage
test -f "binutils-$BINUTILS_V.tar.xz" || download "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_V.tar.xz"
test -f "gcc-$GCC_V.tar.xz"           || download "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_V/gcc-$GCC_V.tar.xz"
test -f "newlib-$NEWLIB_V.tar.gz"     || download "https://sourceware.org/pub/newlib/newlib-$NEWLIB_V.tar.gz"

test -f "gas-vr4300.patch"            || download "https://raw.githubusercontent.com/aglab2/winn64libs/refs/heads/main/gas-vr4300.patch"
test -f "gcc-vr4300.patch"            || download "https://raw.githubusercontent.com/aglab2/winn64libs/refs/heads/main/gcc-vr4300.patch"
test -f "mips_floats.patch"           || download "https://gist.githubusercontent.com/Thar0/a5ecc783b5ef711488c09204b12ef378/raw/ae2752c47349b4c3145aa0b64fc9ede10f2b5635/mips_floats.patch"

# Dependency source: Extract stage
test -d "binutils-$BINUTILS_V" || unzip_and_patch "binutils-$BINUTILS_V" "gas-vr4300.patch" 
test -d "gcc-$GCC_V"           || { \
                                      tar -xJf "gcc-$GCC_V.tar.xz"; \
                                      pushd "gcc-$GCC_V"; \
                                      patch -p1 < "../gcc-vr4300.patch"; \
                                      patch -p1 < "../bb-reorder.patch"; \
                                      patch -p1 < "../mips_floats.patch"; \
                                      patch -p1 < "../mingw.patch"; \
                                      contrib/download_prerequisites; \
                                      popd; \
                                  }
test -d "newlib-$NEWLIB_V"     || tar -xzf "newlib-$NEWLIB_V.tar.gz"

# Compile binutils
cd "binutils-$BINUTILS_V"
CFLAGS="-O2 -std=gnu99 ${MACOS_CFLAGS}" CXXFLAGS="-O2 ${MACOS_CXXFLAGS}" ./configure \
	--disable-debug \
    --enable-checking=release \
    --prefix="$INSTALL_PATH" \
    --target=${MIPS}-elf \
    --with-cpu=mips64vr4300 \
    --program-prefix=mips-n64- \
    --disable-werror \
    $ZLIB_FLAG
make -j "$JOBS"
make install

export RANLIB_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-ranlib
export CC_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-gcc
export CXX_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-g++
export AR_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-ar
export STRIP_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-strip
export CFLAGS_FOR_TARGET="${ABI_FLAGS} ${TARGET_FLAGS} -ffreestanding ${OPT_FLAGS} -O2"
export CXXFLAGS_FOR_TARGET="${ABI_FLAGS} ${TARGET_FLAGS} -ffreestanding ${OPT_FLAGS} -O2"

# Compile GCC for MIPS N64 outside of the source tree
cd ..
rm -rf gcc_compile
mkdir -p gcc_compile
cd gcc_compile
CFLAGS="-O2 ${MACOS_CFLAGS}" CXXFLAGS="-O2 ${MACOS_CXXFLAGS}" \
../"gcc-$GCC_V"/configure \
    --prefix="$INSTALL_PATH" \
    --with-gnu-as=${INSTALL_PATH}/bin/mips-n64-as \
    --with-gnu-ld=${INSTALL_PATH}/bin/mips-n64-ld \
    --target=${MIPS}-elf \
    --program-prefix=mips-n64- \
    --with-arch=vr4300 \
    --with-tune=vr4300 \
    --enable-languages=c \
    --with-newlib \
    --disable-libssp \
    --disable-multilib \
    --disable-shared \
    --with-gcc \
    --disable-threads \
    --disable-win32-registry \
    --disable-nls \
    --disable-werror \
    --with-abi=${ABI} \
    $FP_FLAGS \
    --with-system-zlib \
    --with-specs="${ABI_FLAGS} ${TARGET_FLAGS}" \
    ${MACOS_DISABLE_FLAGS} \
    $ZLIB_FLAG
make clean -j "$JOBS"
make all-gcc -j "$JOBS"
make install-gcc

# Compile newlib

cd ../"newlib-$NEWLIB_V"
./configure \
    --target=${MIPS}-elf \
    --prefix="$INSTALL_PATH" \
    --with-cpu=mips64vr4300 \
    --disable-threads \
    --disable-shared \
    --disable-libssp \
    --disable-werror

# Workaround here. GCC itself has an internal compiler error (ICE) when compiling one of the files,
# so we need to compile it with -O0 to avoid the issue. We need to build until it fails, then build that file separately.

make -j "$JOBS" || true # Hacky workaround for build issues, this will let the script continue
make -C "./${MIPS}-elf/newlib/libm/math" lib_a-kf_rem_pio2.o CFLAGS+=" -O0"
make -j "$JOBS"
make install

# Finish compiling libgcc now that newlib is available

cd ../gcc_compile
make all -j "$JOBS"
make install-strip
cd .. 

echo "The toolchain has been successfully installed to ${INSTALL_PATH}"
