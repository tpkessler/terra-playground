<!--
SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>

SPDX-License-Identifier: CC0-1.0
-->

# Here are some installation notes
The required libraries are
1. Blas
2. Lapack
3. Flint
The notes below are for macos arm64.

## Blas / Lapack installation
Here follow some notes on installation of 'lapack' and 'blas' on macos with apple arm architecture. I expect this to work also on x86.

Apple ships with their own blas and lapack implementation as part of the accelerate framework. Although I could successfully link and test these from C, I could not get it working with terra and got the following error
```
    #error "neon support not enabled"
```
which has to do with vector instructions.

I also tried the precompiled binaries from [homebrew](https://formulae.brew.sh/formula/lapack) but got a segfault when calling lapack functions from terra.

Instead I compiled lapack directly from source. I used the reference Lapack, but you can also try the implementation from [openblas](https://github.com/OpenMathLib/OpenBLAS).

Here I describe the steps:

1. First clone the official [Lapack](https://github.com/Reference-LAPACK/lapack) repo.
```
    git clone https://github.com/Reference-LAPACK/lapack.git
```
2. Build and install with cmake:
```
    cd lapack
    mkdir build
    cd build
```
The build options are important here. We require the C-wrappers provided by LAPACKE. The `64_EXT_API` implementation needs to be turned off and we build using shared libraries. Also, we directly build the provided blas implementation. Clearly, you can use your own. Check the cmake files in the lapack source to check how to do that.
```
cmake -DCMAKE_INSTALL_PREFIX=/usr/local/lib/lapack .. -DLAPACKE=on -DBUILD_TESTING=on -DBUILD_INDEX64_EXT_API=off -DCBLAS=on -DBUILD_SHARED_LIBS=on
cmake --build . -j8 --target install
ctest .
```
3. As installation folder I used `/usr/local/lib/lapack`. In order for macos to find the include and shared libraries contained therein, add the following lines to your zprofile:
```
export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/lib/lapack/lib:${DYLD_FALLBACK_LIBRARY_PATH}"
export INCLUDE_PATH="/usr/local/lib/lapack/include;${INCLUDE_PATH}"
```

## Flint
The easiest way is to add Flint via homebrew. You need to use the latest version of Flint, because we have a dependency on `nfloat.h`. You can install it using
```
    brew install flint --HEAD
```
Make sure terra can find the shared libraries and includes by adding the following two lines:
```
    export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/Cellar/flint/HEAD-02d4e5d/lib/:${DYLD_FALLBACK_LIBRARY_PATH}"
    export INCLUDE_PATH="/opt/homebrew/Cellar/flint/HEAD-02d4e5d/include;/opt/homebrew/Cellar/gmp/6.3.0/include;${INCLUDE_PATH}"
```
