#/bin/bash

# This script will install ghc + cabal + happy + conjure.
# It will only install these tools if they aren't already installed.
#
# Everything is installed locally. Except ~/.ghc and ~/.cabal.
# These two directories are used by ghc and cabal for storing some metadata
# and data about installed packages.
#
# To clean an installation:
#     rm -rf dist ~/.ghc ~/.cabal


set -o errexit
set -o nounset

OS=$(uname)

if [ "$OS" == "Darwin" ]; then
    PLATFORM="apple-darwin"
elif [ "$OS" == "Linux" ]; then
    PLATFORM="unknown-linux"
else
    echo "Cannot determine your OS, uname reports: ${OS}"
    exit 1
fi

JOBS="0"
if [ $# -eq 1 ]; then
    JOBS="$1"
fi

if [ $JOBS -eq 0 ]; then
    CORES=$( (grep -c ^processor /proc/cpuinfo 2> /dev/null) || (sysctl hw.logicalcpu | awk '{print $2}' 2> /dev/null) || 0 )
    if [ $CORES -eq 0 ]; then
        echo "Cannot tell how many cores the machine has. Will use only 1."
    else
        echo "This machine seems to have $CORES cores. Will use all."
        JOBS=$CORES
    fi
fi

WD="$(pwd)"
mkdir -p dist/tools
cd dist/tools

export PATH="$WD/dist/tools/ghc-7.6.3-build/bin":$PATH
export PATH="$HOME/.cabal/bin":$PATH

HAS_LLVM="$(opt -version 2> /dev/null | grep -i llvm | wc -l | tr -d ' ')"


# installing ghc
if [ "$(ghc --version)" != "The Glorious Glasgow Haskell Compilation System, version 7.6.3" ]; then
    echo "Installing GHC"
    wget -c "http://www.haskell.org/ghc/dist/7.6.3/ghc-7.6.3-x86_64-${PLATFORM}.tar.bz2"
    tar xvjf "ghc-7.6.3-x86_64-${PLATFORM}.tar.bz2"
    cd ghc-7.6.3
    ./configure --prefix="$WD/dist/tools/ghc-7.6.3-build"
    make install
    cd ..
    rm -rf "ghc-7.6.3-x86_64-${PLATFORM}.tar.bz2" ghc-7.6.3
fi


# installing cabal-install
if [ "$(cabal --version | head -n 1)" != "cabal-install version 1.18.0.2" ]; then
    echo "Installing cabal-install"
    wget -c http://hackage.haskell.org/packages/archive/cabal-install/1.18.0.2/cabal-install-1.18.0.2.tar.gz
    tar -zxvf cabal-install-1.18.0.2.tar.gz
    cd cabal-install-1.18.0.2
    bash bootstrap.sh
    cd ..
    rm -rf cabal-install-1.18.0.2.tar.gz cabal-install-1.18.0.2
fi

cd "$WD"
cabal update

# installing happy
HAS_HAPPY="$(which happy 2> /dev/null > /dev/null ; echo $?)" 
if [ "$HAS_HAPPY" != 0 ] ; then
    echo "Installing happy"
    mkdir -p dist/tools
    pushd dist/tools
    cabal install happy -O2 \
        --force-reinstalls \
        --disable-documentation \
        --disable-library-profiling \
        --disable-executable-profiling
    popd
fi

ghc --version
cabal --version
happy --version

VERSION=$(hg id -i | head -n 1)
echo "module RepositoryVersion where"       >  src/RepositoryVersion.hs
echo "repositoryVersion :: String"          >> src/RepositoryVersion.hs
echo "repositoryVersion = \"${VERSION}\""   >> src/RepositoryVersion.hs

# install conjure, finally
if (( "$HAS_LLVM" > 0 )) && [ "$OS" = "Linux" ] ; then
    echo "Using LLVM"
    scripts/build/make -Ol "-j${JOBS}"
else
    echo "Not using LLVM"
    scripts/build/make -O  "-j${JOBS}"
fi

