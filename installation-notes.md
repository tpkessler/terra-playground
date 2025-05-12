<!--
SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>

SPDX-License-Identifier: CC0-1.0
-->

# Here are some installation notes
The required libraries are
1. OpenBlas (ships with Lapack)
3. Flint
The notes below are for macos arm64.

## OpenBlas installation
Here follow some notes on installation of [openblas](https://github.com/OpenMathLib/OpenBLAS) on macos with apple arm architecture. I expect this to work also on x86 and on linux machines. Apple ships with their own blas and lapack implementation as part of the accelerate framework, However, it's difficult to get these working correctly. [homebrew](https://formulae.brew.sh/formula/lapack) has precompiled binaries but I got a segfault on my system when calling lapack functions from terra.

Instead, I recommend installing [openblas](https://github.com/OpenMathLib/OpenBLAS) from source, following these instructions

1. First clone the official [openblas](https://github.com/OpenMathLib/OpenBLAS) repo.
```
    git clone https://github.com/OpenMathLib/OpenBLAS.git
```
2. Build and install with cmake:
```
    cd OpenBlas
    mkdir build
    cd build
```
The build options are important here. We require a build with shared libraries
```
cmake -DCMAKE_INSTALL_PREFIX=/usr/local/lib/openblas .. -DBUILD_TESTING=on -DBUILD_SHARED_LIBS=on
cmake --build . -j8 --target install
ctest .
```
3. As installation folder I used `/usr/local/lib/openblas`. In order for macos to find the include and shared libraries contained therein, add the following lines to your zprofile:
```
export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/lib/openblas/lib:${DYLD_FALLBACK_LIBRARY_PATH}"
export INCLUDE_PATH="/usr/local/lib/openblas/include;${INCLUDE_PATH}"
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
