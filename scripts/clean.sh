#!/usr/bin/env bash

echo Cleaning started

# Reset watchman watches for this project only
if command -v watchman &> /dev/null; then
  echo "Resetting watchman watches for this project"
  watchman watch-del . 2>/dev/null || echo "No watch found for this directory"
fi

rm -rf .tsbuildinfo.precommit
rm -rf ios/Pods
rm -rf node_modules
rm -rf dist
rm -rf ios/build
rm -rf android/app/build

# Metadata CMake cua NDK luu duong dan TUYET DOI toi CMakeLists.txt sinh boi codegen cua
# tung thu vien trong node_modules. Xoa node_modules ma khong xoa .cxx se de lai cac duong
# dan tro vao hu khong, va lan build sau that bai voi:
#   [CXX1409] expected buildFiles file '.../build/generated/source/codegen/jni/CMakeLists.txt' to exist
rm -rf android/app/.cxx
rm assets/fonts/compass-icons.ttf
rm android/app/src/main/assets/fonts/compass-icons.ttf

echo Cleanup finished