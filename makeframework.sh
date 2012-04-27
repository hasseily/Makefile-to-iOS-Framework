#!/bin/bash

################################################################################
#
# Copyright (c) 2008-2010 Christopher J. Stawarz and Henri Asseily
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
################################################################################



# Disallow undefined variables
set -u


default_gcc_version=4.2
default_iphoneos_version=4.3
default_macos_version=10.6

GCC_VERSION="${GCC_VERSION:-$default_gcc_version}"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-$default_iphoneos_version}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$default_macos_version}"


usage ()
{
    cat >&2 << EOF
Usage: ${0##*/} [-ht] [-p prefix] [-v version] target [configure_args]
  -h  Print help message
  -p  Installation prefix (default: \$HOME/compiles/Platform/...)
  -t  Use 16-bit Thumb instruction set (instead of 32-bit ARM)
  -v  Set the framework version (default: 1.0.0)

The target must be "armv6", "armv7", "simulator" or "framework".
The "framework" target builds a fat static library framework.
Use the "framework" target only on makefiles that create a single
static library.

Any additional arguments are passed to configure.

The following environment variables affect the build process:

  GCC_VERSION     (default: $default_gcc_version)
  IPHONEOS_DEPLOYMENT_TARGET  (default: $default_iphoneos_version)
  MACOSX_DEPLOYMENT_TARGET  (default: $default_macos_version)

Example:

  ${0##*/} -v 1.0.2 framework --disable-shared --enable-static --disable-gost --disable-sha2 --without-ssl
EOF
}


while getopts ":hp:tv:" opt; do
    case $opt in
  h  ) usage ; exit 0 ;;
  p  ) prefix="$OPTARG" ;;
  t  ) thumb_opt=thumb ;;
  v  ) version="$OPTARG" ;;
  \? ) usage ; exit 2 ;;
    esac
done
shift $(( $OPTIND - 1 ))

if (( $# < 1 )); then
    usage
    exit 2
fi

target=$1
shift

case $target in

    armv6 )
  arch=armv6
  platform=iPhoneOS
  extra_cflags="-m${thumb_opt:-no-thumb} -mthumb-interwork"
  ;;

    armv7 )
  arch=armv7
  platform=iPhoneOS
  extra_cflags="-m${thumb_opt:-no-thumb} -mthumb-interwork"
  ;;

    simulator )
  arch=i386
  platform=iPhoneSimulator
  extra_cflags="-D__IPHONE_OS_VERSION_MIN_REQUIRED=${IPHONEOS_DEPLOYMENT_TARGET%%.*}0000"
  ;;

    framework )
  platform=iPhoneFramework
  prefix="${prefix:-${HOME}/compiles/${platform}}"
  version="${version:-1.0.0}"
  echo "Creating fat library for Release"
  $0 ${thumb_opt:+-t} -p "${prefix}/iPhoneSimulator" simulator $@
  $0 ${thumb_opt:+-t} -p "${prefix}/iPhoneOS_armv6" armv6 $@
  $0 ${thumb_opt:+-t} -p "${prefix}/iPhoneOS_armv7" armv7 $@
  libname=`ls ${prefix}/iPhoneSimulator/lib/*.a | sed -E -e 's/^.*\/lib\/([^\/]+)$/\1/'`
  productname=`echo ${libname} | sed -E -e 's/lib([^.]+)\.a/\1/g'`
  mkdir -p "${prefix}/lib"
  lipo "${prefix}/iPhoneSimulator/lib/${libname}" "${prefix}/iPhoneOS_armv6/lib/${libname}" "${prefix}/iPhoneOS_armv7/lib/${libname}" -output "${prefix}/lib/${libname}" -create

  if [ -d "${prefix}/${productname}.framework" ]
  then
    rm -rf "${prefix}/${productname}.framework"
  fi

  echo "Creating skeleton framework"
  tar xf "./Canonical.framework.tar" -C "${prefix}/"
  mv "${prefix}/Canonical.framework" "${prefix}/${productname}.framework"

  lipo "${prefix}/iPhoneSimulator/lib/${libname}" "${prefix}/iPhoneOS_armv6/lib/${libname}" "${prefix}/iPhoneOS_armv7/lib/${libname}" -output "${prefix}/${productname}.framework/Versions/A/${productname}" -create
  
  echo "Finishing packaging framework"
  ln -s "Versions/A/${productname}" "${prefix}/${productname}.framework/"
  cp -r "${prefix}/iPhoneSimulator/include/" "${prefix}/${productname}.framework/Versions/A/Headers/"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "${prefix}/${productname}.framework/Versions/A/Resources/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.makefile.${productname}" "${prefix}/${productname}.framework/Versions/A/Resources/Info.plist"

  echo "Completed build of ${productname} framework"
  exit 0

  ;;

    * )
  usage
  exit 2

esac


platform_dir="/Developer/Platforms/${platform}.platform/Developer"
platform_bin_dir="${platform_dir}/usr/bin"
platform_sdk_dir="${platform_dir}/SDKs/${platform}${IPHONEOS_DEPLOYMENT_TARGET}.sdk"
prefix="${prefix:-${HOME}/compiles/${platform}}"

export CC="${platform_bin_dir}/llvm-gcc-${GCC_VERSION}"
export CFLAGS="-arch ${arch} -pipe -Os -gdwarf-2 -isysroot ${platform_sdk_dir} ${extra_cflags}"
export LDFLAGS="-arch ${arch} -isysroot ${platform_sdk_dir}"
export CXX="${platform_bin_dir}/llvm-g++-${GCC_VERSION}"
export CXXFLAGS="${CFLAGS}"
export CPP="/Developer/usr/bin/llvm-cpp-${GCC_VERSION}"
export CXXCPP="${CPP}"

make clean

# make install has a bug in that it looks for include/ldns/util.h instead of ldns/util.h
mkdir include
ln -s ../ldns include/ldns

./configure \
    --prefix="${prefix}" \
    --host="${arch}-apple-darwin" \
    --disable-shared \
    --enable-static \
    "$@" || exit

make install || exit

cat >&2 << EOF

${target} build succeeded!  Files were installed in

  $prefix

EOF
