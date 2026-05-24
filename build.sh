#!/usr/bin/env sh

cmake -B build -S . -DFFMPEG_PREPARED_BINARIES=$FFMPEG_PREPARED_BINARIES/ffmpeg -DUDEV_FOUND=true -DSYSTEMD_FOUND=true -DBOOST_USE_STATIC=false -DBUILD_DOCS=false -DBUILD_TESTS=false -DSUNSHINE_ENABLE_CUDA=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=1

cmake --build build --target sunshine -j$(nproc)
