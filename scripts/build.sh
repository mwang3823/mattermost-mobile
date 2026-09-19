#!/usr/bin/env bash

# Toan bo cau hinh build nam trong assets/base/config.json (khoi "Build").
# Doc + ap dung xuong project TRUOC khi build, roi sinh env cho Fastlane.
function readBuildConfig() {
    echo "Reading build configuration from assets/base/config.json"
    node scripts/build_config.js --apply || exit 1

    # Keystore/signing info is exported as ORG_GRADLE_PROJECT_* so Gradle picks it
    # up from the environment (no passwords on the command line).
    eval "$(node scripts/build_config.js --shell)" || exit 1
}

function execute() {
    local platform=$1
    local lane=$2
    local default_env=$3
    local fastlane_env="${FASTLANE_ENV:-$default_env}"
    local env_args=()

    if [[ -n "$fastlane_env" ]]; then
        if [[ -f "fastlane/.env.${fastlane_env}" ]]; then
            env_args=(--env "$fastlane_env")
            echo "Using fastlane env: ${fastlane_env}"
        else
            echo "fastlane/.env.${fastlane_env} not found, building with default values"
        fi
    fi

    cd fastlane && NODE_ENV=production bundle exec fastlane "$platform" "$lane" "${env_args[@]}"
}

function apk() {
  readBuildConfig
  case $1 in
    unsigned)
      echo "Building Android unsigned app"
      setup android
      execute android unsigned generated.android
    ;;
    *)
      echo "Building Android app"
      setup android
      execute android build generated.android
  esac
}

function ipa() {
  readBuildConfig
  case $1 in
    unsigned)
      echo "Building iOS unsigned app"
      setup ios
      execute ios unsigned generated.ios
    ;;
    simulator)
      echo "Building unsigned iOS app for iPhone simulator"
      setup ios
      execute ios simulator generated.ios
    ;;
    *)
      echo "Building iOS app"
      setup ios
      execute ios build generated.ios
  esac
}

function installGemsAndPods() {
    echo "Installing Gems"
    npm run ios-gems
    echo "Getting Cocoapods dependencies"
    npm run pod-install
}

function setup() {
    if [[ -z "$SKIP_SETUP" ]]; then
        npm run clean || exit 1
        npm install --ignore-scripts || exit 1

        # postinstall.sh is skipped by --ignore-scripts; copy the font manually
        cp "node_modules/@mattermost/compass-icons/font/compass-icons.ttf" "assets/fonts/" || exit 1
        cp "node_modules/@mattermost/compass-icons/font/compass-icons.ttf" "android/app/src/main/assets/fonts/" || exit 1

        npx patch-package || exit 1

        node node_modules/\@sentry/cli/scripts/install.js || exit 1

        if [[ "$1" == "ios"* ]]; then
          installGemsAndPods || exit 1
        fi

        ASSETS=$(node scripts/generate-assets.js)
        if [ -z "$ASSETS" ]; then
            echo "Error Generating app assets"
            exit 1
        else
            echo "Generating app assets"
        fi

        COMPASS_ICONS="node_modules/@mattermost/compass-icons/font/compass-icons.ttf"
        GENERATE_GLYPH_MAP_SCRIPT="scripts/generate-compass-glyph-map.mjs"

        if [ ! -f "$COMPASS_ICONS" ]; then
            echo "Compass Icons font not found at: $COMPASS_ICONS"
            exit 1
        fi

        if [ ! -f "$GENERATE_GLYPH_MAP_SCRIPT" ]; then
            echo "Compass glyph map script not found at: $GENERATE_GLYPH_MAP_SCRIPT"
            exit 1
        fi

        echo "Generating Compass Icons glyph map"
        node "$GENERATE_GLYPH_MAP_SCRIPT"

        echo "Installing Fastane"
        if !gem list bundler -i --version 2.5.11 > /dev/null 2>&1; then
          gem install bundler --versio 2.5.11
        fi
        cd fastlane && bundle install && cd .. || exit 1
    fi

    if [ "$1" = "android" ]; then
      ./node_modules/.bin/jetify
    fi
}

case $1 in
  apk)
    apk $2
  ;;
  ipa)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      ipa $2
    else
      echo "You need a MacOS to build the iOS mobile app"
      exit 1
    fi
  ;;
  *)
    echo "Build the mobile app for Android or iOS
    Usage: build.sh <type> [options]
    
    Type:
      apk   Builds Android APK(s)
      ipa   Builds iOS IPA
      
    Options:
      apk: unsigned
      ipa: unsigned or simulator"
  ;;
esac
