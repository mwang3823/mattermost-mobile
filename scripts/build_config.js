#!/usr/bin/env node
// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

/* eslint-disable no-console, max-lines */

//
// build_config.js — đọc khối "Build" trong assets/base/config.json rồi áp dụng
// xuống các file cấu hình native (Gradle, AndroidManifest, strings.xml,
// project.pbxproj, Info.plist, entitlements) + sinh env cho Fastlane.
//
// config.json là NGUỒN DUY NHẤT: sửa ở đó rồi build, đừng sửa tay file native.
//
//   node scripts/build_config.js              # xem cấu hình
//   node scripts/build_config.js --apply      # áp dụng xuống project
//   node scripts/build_config.js --check      # chỉ kiểm tra, lệch thì exit 1
//   node scripts/build_config.js --shell      # xuất biến cho tdc.sh
//   node scripts/build_config.js --gradle-args
//   node scripts/build_config.js --fastlane-env <android|ios>
//   node scripts/build_config.js --json
//   node scripts/build_config.js --envs       # liệt kê môi trường server
//   node scripts/build_config.js --env <tên>  # chọn môi trường (ghi Build.Environment)
//

'use strict';

const {execFileSync} = require('child_process');
const fs = require('fs');
const path = require('path');

const {selectedEnv, toAppConfig} = require('./app_env');

const ROOT = path.resolve(__dirname, '..');
const CONFIG_FILE = path.join(ROOT, 'assets/base/config.json');
const GEN_ENV_ANDROID = 'fastlane/.env.generated.android';
const GEN_ENV_IOS = 'fastlane/.env.generated.ios';
const KNOWN_ABIS = ['armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'];
const IS_MAC = process.platform === 'darwin';

const ESC = String.fromCharCode(27);
const RED = `${ESC}[31m`;
const GRN = `${ESC}[32m`;
const YLW = `${ESC}[33m`;
const DIM = `${ESC}[2m`;
const BLD = `${ESC}[1m`;
const RST = `${ESC}[0m`;

// ------------------------------------------------------------------ tiện ích
function fail(msg) {
    console.error(`${RED}cấu hình không hợp lệ:${RST} ${msg}`);
    process.exit(1);
}

function readFile(rel) {
    return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

function fileExists(rel) {
    return fs.existsSync(path.isAbsolute(rel) ? rel : path.join(ROOT, rel));
}

function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Thay ${TÊN_BIẾN} bằng giá trị biến môi trường; không có thì trả về ''
function resolveValue(value, unresolved) {
    if (typeof value === 'string') {
        return value.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => {
            // eslint-disable-next-line no-process-env
            const found = process.env[name];
            if (found === undefined || found === '') {
                unresolved.add(name);
                return '';
            }
            return found;
        });
    }
    if (Array.isArray(value)) {
        return value.map((v) => resolveValue(v, unresolved));
    }
    if (value && typeof value === 'object') {
        const out = {};
        for (const [k, v] of Object.entries(value)) {
            out[k] = resolveValue(v, unresolved);
        }
        return out;
    }
    return value;
}

// Giữ chuỗi gốc để biết giá trị nào là placeholder (bí mật) — những giá trị đó
// không được ghi vào file env sinh ra, Fastlane tự đọc từ môi trường.
function isPlaceholder(raw) {
    return typeof raw === 'string' && /\$\{[A-Za-z_][A-Za-z0-9_]*\}/.test(raw);
}

function loadConfig() {
    let raw;
    try {
        raw = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch (e) {
        fail(`không đọc được ${path.relative(ROOT, CONFIG_FILE)}: ${e.message}`);
    }
    if (!raw.Build) {
        fail('thiếu khối "Build" trong assets/base/config.json');
    }
    const unresolved = new Set();
    const cfg = resolveValue(raw, unresolved);
    cfg.__raw = raw;
    cfg.__env = selectedEnv(raw);
    cfg.__unresolved = [...unresolved];
    return cfg;
}

// --------------------------------------------------------------- kiểm tra
const PKG_RE = /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/;
const SEMVER_RE = /^\d+\.\d+\.\d+$/;

function validate(cfg) {
    const b = cfg.Build;
    const errors = [];
    const need = (cond, msg) => {
        if (!cond) {
            errors.push(msg);
        }
    };

    const envs = b.Environments || {};
    if (cfg.__env) {
        need(Boolean(envs[cfg.__env]), `môi trường "${cfg.__env}" không có trong Build.Environments (${Object.keys(envs).join(', ')})`);
    }
    for (const [name, env] of Object.entries(envs)) {
        need(/^https?:\/\/[^\s/]+/.test(String(env && env.DefaultServerUrl)), `Build.Environments.${name}.DefaultServerUrl phải là URL http(s)`);
    }

    need(Boolean(b.App && b.App.name), 'Build.App.name không được để trống');
    need(SEMVER_RE.test(String(b.App && b.App.version)), 'Build.App.version phải dạng x.y.z');
    need(Number.isInteger(b.App && b.App.buildNumber) && b.App.buildNumber > 0, 'Build.App.buildNumber phải là số nguyên > 0');
    need(Boolean(b.App) && /^[a-z][a-z0-9+.-]*$/.test(String(b.App.scheme)), 'Build.App.scheme phải là url scheme hợp lệ');

    const a = b.Android || {};
    need(PKG_RE.test(String(a.applicationId)), 'Build.Android.applicationId không hợp lệ');
    need(PKG_RE.test(String(a.javaPackage)), 'Build.Android.javaPackage không hợp lệ');
    need(String(a.mainActivity).startsWith(`${a.javaPackage}.`), 'Build.Android.mainActivity phải nằm trong javaPackage');
    for (const k of ['minSdk', 'compileSdk', 'targetSdk']) {
        need(Number.isInteger(a[k]) && a[k] >= 21, `Build.Android.${k} phải là số nguyên >= 21`);
    }
    need(Array.isArray(a.architectures) && a.architectures.length > 0, 'Build.Android.architectures không được rỗng');
    if (Array.isArray(a.architectures)) {
        for (const abi of a.architectures) {
            need(KNOWN_ABIS.includes(abi), `Build.Android.architectures: "${abi}" không hợp lệ (${KNOWN_ABIS.join(', ')})`);
        }
    }
    for (const task of String(a.buildTask || '').split(',')) {
        need(['assemble', 'bundle'].includes(task.trim()), 'Build.Android.buildTask chỉ nhận assemble và/hoặc bundle');
    }
    const sign = a.signing || {};
    if (sign.storeFile) {
        need(fileExists(sign.storeFile), `Build.Android.signing.storeFile không tồn tại: ${sign.storeFile}`);
        need(Boolean(sign.keyAlias), 'Build.Android.signing.keyAlias không được trống khi đã khai storeFile');
        need(Boolean(sign.storePassword), 'Build.Android.signing.storePassword trống (đặt biến môi trường tương ứng)');
    }
    if (a.googleServicesFile) {
        need(fileExists(a.googleServicesFile), `Build.Android.googleServicesFile không tồn tại: ${a.googleServicesFile}`);
    }

    const i = b.Ios || {};
    need(PKG_RE.test(String(i.bundleId)), 'Build.Ios.bundleId không hợp lệ');
    need(String(i.shareExtensionBundleId).startsWith(`${i.bundleId}.`), 'Build.Ios.shareExtensionBundleId phải bắt đầu bằng bundleId');
    need(String(i.notificationServiceBundleId).startsWith(`${i.bundleId}.`), 'Build.Ios.notificationServiceBundleId phải bắt đầu bằng bundleId');
    need(String(i.appGroup).startsWith('group.'), 'Build.Ios.appGroup phải bắt đầu bằng "group."');
    need(String(i.icloudContainer).startsWith('iCloud.'), 'Build.Ios.icloudContainer phải bắt đầu bằng "iCloud."');
    need(Boolean(i.keychainGroup), 'Build.Ios.keychainGroup không được trống');
    need(['development', 'production'].includes(String(i.apsEnvironment)), 'Build.Ios.apsEnvironment chỉ nhận "development" hoặc "production"');
    if (i.intune && i.intune.enabled) {
        need(Boolean(i.intune.clientId), 'Build.Ios.intune.clientId bắt buộc khi intune.enabled = true');
    }

    if (errors.length) {
        console.error(`${RED}  Cấu hình không hợp lệ:${RST}`);
        for (const e of errors) {
            console.error(`   - ${e}`);
        }
        process.exit(1);
    }
}

// --------------------------------------------------------- danh sách thay đổi
// Mỗi phần tử: {file, label, value, current, apply(text) -> text}
function textEdit(edits, file, label, re, value) {
    if (!fileExists(file)) {
        return;
    }
    const text = readFile(file);
    const m = text.match(re);
    if (!m) {
        edits.push({file, label, value: String(value), current: null, missing: true});
        return;
    }
    edits.push({
        file,
        label,
        value: String(value),
        current: m[1],
        apply(src) {
            // re không có cờ 'g' nên chỉ thay lần xuất hiện đầu tiên; dùng hàm
            // replace để giá trị có ký tự $ không bị hiểu là mẫu thay thế
            return src.replace(re, (whole, cur) => whole.replace(cur, () => String(value)));
        },
    });
}

// Thay MỌI lần xuất hiện, dùng cho project.pbxproj (mỗi setting nằm ở nhiều
// build configuration khác nhau)
function textEditAll(edits, file, label, re, pick) {
    if (!fileExists(file)) {
        return;
    }
    const matches = [...readFile(file).matchAll(re)];
    if (matches.length === 0) {
        edits.push({file, label, value: '', current: null, missing: true});
        return;
    }
    const currents = [...new Set(matches.map((m) => m[1]))];
    const wanted = [...new Set(matches.map((m) => pick(m[1])))];
    edits.push({
        file,
        label,
        value: wanted.join(', '),
        current: currents.join(', '),
        apply(src) {
            return src.replace(new RegExp(re.source, re.flags), (whole, cur) => whole.replace(cur, pick(cur)));
        },
    });
}

// Thay <string> đầu tiên sau <key>...</key> trong plist/entitlements XML
function plistEdit(edits, file, key, label, value) {
    const re = new RegExp(`<key>${escapeRe(key)}</key>\\s*(?:<array>\\s*)?<string>([^<]*)</string>`);
    textEdit(edits, file, label, re, value);
}

function authSchemes(cfg) {
    return {
        auth: String(cfg.AuthUrlScheme || 'mmauth://').replace(/:\/\/$/, ''),
        authDev: String(cfg.AuthUrlSchemeDev || 'mmauthbeta://').replace(/:\/\/$/, ''),
    };
}

function buildEdits(cfg) {
    const b = cfg.Build;
    const app = b.App;
    const a = b.Android;
    const i = b.Ios;
    const edits = [];
    const {auth, authDev} = authSchemes(cfg);

    // ------------------------------------------------------------- Android
    const appGradle = 'android/app/build.gradle';
    textEdit(edits, appGradle, 'applicationId', /applicationId\s+"([^"]*)"/, a.applicationId);
    textEdit(edits, appGradle, 'namespace', /namespace\s+"([^"]*)"/, a.javaPackage);
    textEdit(edits, appGradle, 'versionCode', /versionCode\s+(\d+)/, app.buildNumber);
    textEdit(edits, appGradle, 'versionName', /versionName\s+"([^"]*)"/, app.version);

    const rootGradle = 'android/build.gradle';
    textEdit(edits, rootGradle, 'minSdkVersion', /minSdkVersion\s*=\s*(\d+)/, a.minSdk);
    textEdit(edits, rootGradle, 'compileSdkVersion', /compileSdkVersion\s*=\s*(\d+)/, a.compileSdk);
    textEdit(edits, rootGradle, 'targetSdkVersion', /targetSdkVersion\s*=\s*(\d+)/, a.targetSdk);
    textEdit(edits, rootGradle, 'buildToolsVersion', /buildToolsVersion\s*=\s*"([^"]*)"/, a.buildTools);
    textEdit(edits, rootGradle, 'ndkVersion', /ndkVersion\s*=\s*"([^"]*)"/, a.ndk);

    const gradleProps = 'android/gradle.properties';
    textEdit(edits, gradleProps, 'reactNativeArchitectures', /^reactNativeArchitectures=(.*)$/m, a.architectures.join(','));
    textEdit(edits, gradleProps, 'newArchEnabled', /^newArchEnabled=(.*)$/m, Boolean(a.newArch));
    textEdit(edits, gradleProps, 'hermesEnabled', /^hermesEnabled=(.*)$/m, Boolean(a.hermes));
    textEdit(edits, gradleProps, 'edgeToEdgeEnabled', /^edgeToEdgeEnabled=(.*)$/m, Boolean(a.edgeToEdge));

    textEdit(edits, 'android/app/src/main/res/values/strings.xml', 'app_name',
        /<string name="app_name">([^<]*)<\/string>/, app.name);

    // AndroidManifest có đúng 3 dòng scheme, theo thứ tự: app, auth, auth-dev
    const manifest = 'android/app/src/main/AndroidManifest.xml';
    if (fileExists(manifest)) {
        const schemeRe = /<data android:scheme="([^"]*)"\s*\/>/g;
        const wanted = [app.scheme, auth, authDev];
        const found = [...readFile(manifest).matchAll(schemeRe)];
        if (found.length === wanted.length) {
            edits.push({
                file: manifest,
                label: 'schemes',
                current: found.map((m) => m[1]).join(', '),
                value: wanted.join(', '),
                apply(src) {
                    let n = 0;
                    return src.replace(new RegExp(schemeRe.source, 'g'), (whole, cur) => {
                        const next = wanted[n++];
                        return next ? whole.replace(cur, next) : whole;
                    });
                },
            });
        } else {
            edits.push({
                file: manifest,
                label: 'schemes',
                current: found.map((m) => m[1]).join(', '),
                value: wanted.join(', '),
                skip: `cần đúng ${wanted.length} dòng android:scheme, tìm thấy ${found.length} — sửa tay`,
            });
        }
    }

    // package.json giữ cùng version để màn hình About và npm khớp nhau
    textEdit(edits, 'package.json', 'version', /^  "version": "([^"]*)"/m, app.version);

    // ----------------------------------------------------------------- iOS
    const pbx = 'ios/Mattermost.xcodeproj/project.pbxproj';
    textEditAll(edits, pbx, 'PRODUCT_BUNDLE_IDENTIFIER', /PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g, (cur) => {
        if (cur.endsWith('.MattermostShare')) {
            return i.shareExtensionBundleId;
        }
        if (cur.endsWith('.NotificationService')) {
            return i.notificationServiceBundleId;
        }
        return i.bundleId;
    });
    textEditAll(edits, pbx, 'CURRENT_PROJECT_VERSION', /CURRENT_PROJECT_VERSION = ([^;]+);/g, () => String(app.buildNumber));
    if (i.teamId) {
        textEditAll(edits, pbx, 'DEVELOPMENT_TEAM', /DEVELOPMENT_TEAM = ([^;]+);/g, () => i.teamId);
    }

    const plists = [
        ['ios/Mattermost/Info.plist', i.displayName],
        ['ios/MattermostShare/Info.plist', null],
        ['ios/NotificationService/Info.plist', null],
    ];
    for (const [file, displayName] of plists) {
        plistEdit(edits, file, 'CFBundleShortVersionString', 'CFBundleShortVersionString', app.version);
        plistEdit(edits, file, 'CFBundleVersion', 'CFBundleVersion', app.buildNumber);
        plistEdit(edits, file, 'AppGroupIdentifier', 'AppGroupIdentifier', i.appGroup);
        if (displayName) {
            plistEdit(edits, file, 'CFBundleDisplayName', 'CFBundleDisplayName', displayName);
        }
    }

    // Danh sách url scheme của app (bật Intune thì Fastlane tự quản lý danh sách này)
    const mainPlist = 'ios/Mattermost/Info.plist';
    if (!(i.intune && i.intune.enabled) && fileExists(mainPlist)) {
        const arrRe = /(<key>CFBundleURLSchemes<\/key>\s*<array>)([\s\S]*?)(<\/array>)/;
        const m = readFile(mainPlist).match(arrRe);
        if (m) {
            const current = [...m[2].matchAll(/<string>([^<]*)<\/string>/g)].map((x) => x[1]);
            const wanted = [app.scheme, auth];
            const indent = (m[2].match(/\n([ \t]*)<string>/) || [null, '\t\t\t\t'])[1];
            edits.push({
                file: mainPlist,
                label: 'CFBundleURLSchemes',
                current: current.join(', '),
                value: wanted.join(', '),
                apply(src) {
                    const body = `\n${wanted.map((s) => `${indent}<string>${s}</string>`).join('\n')}\n${indent.slice(0, -1)}`;
                    return src.replace(arrRe, (whole, open, _mid, close) => open + body + close);
                },
            });
        }
    }

    const entitlements = [
        ['ios/Mattermost/Mattermost.entitlements', true],
        ['ios/MattermostShare/MattermostShare.entitlements', false],
        ['ios/NotificationService/NotificationService.entitlements', false],
    ];
    for (const [file, isMain] of entitlements) {
        plistEdit(edits, file, 'com.apple.security.application-groups', 'application-groups', i.appGroup);
        if (isMain) {
            plistEdit(edits, file, 'aps-environment', 'aps-environment', i.apsEnvironment);
            plistEdit(edits, file, 'com.apple.developer.icloud-container-identifiers', 'icloud-container', i.icloudContainer);
            plistEdit(edits, file, 'com.apple.developer.ubiquity-container-identifiers', 'ubiquity-container', i.icloudContainer);
            plistEdit(edits, file, 'keychain-access-groups', 'keychain-access-groups', `$(AppIdentifierPrefix)${i.keychainGroup}`);
        }
    }

    return edits;
}

// ---------------------------------------------------------- env cho Fastlane
function fastlaneEnv(cfg, platform) {
    const b = cfg.Build;
    const rawSentry = (cfg.__raw.Build || {}).Sentry || {};
    const app = b.App;
    const a = b.Android;
    const i = b.Ios;
    const f = b.Fastlane || {};
    const s = b.Sentry || {};
    const {auth, authDev} = authSchemes(cfg);
    const bool = (v) => (v ? 'true' : 'false');

    const env = {
        APP_SCHEME: app.scheme,
        APP_AUTH_SCHEME: auth,
        APP_AUTH_SCHEME_BETA: authDev,
        VERSION_NUMBER: app.version,
        BUILD_NUMBER: app.buildNumber,
        BETA_BUILD: bool(f.betaBuild),
        BUILD_FOR_RELEASE: bool(f.buildForRelease),
        REPLACE_ASSETS: bool(f.replaceAssets),
        SHOW_REVIEW: bool(cfg.ShowReview),
        SHOW_ONBOARDING: bool(cfg.ShowOnboarding),
        COLLECT_NETWORK_METRICS: bool(cfg.CollectNetworkMetrics),
        SENTRY_ENABLED: bool(cfg.SentryEnabled),
        SENTRY_ORG: s.org,
        SENTRY_URL: s.url,
    };

    if (cfg.RudderApiKey) {
        env.RUDDER_API_KEY = cfg.RudderApiKey;
    }

    // Token/mật khẩu lấy từ ${BIẾN_MÔI_TRƯỜNG} thì không ghi ra file env
    if (!isPlaceholder(rawSentry.authToken) && s.authToken) {
        env.SENTRY_AUTH_TOKEN = s.authToken;
    }

    if (platform === 'android') {
        Object.assign(env, {
            APP_NAME: app.name,
            MAIN_APP_IDENTIFIER: a.applicationId,

            // Fastlane mặc định đổi cả package Java theo applicationId (và di
            // chuyển source). Bản fork giữ nguyên package Java nên truyền riêng.
            ANDROID_JAVA_PACKAGE: a.javaPackage,

            // Các scheme trong AndroidManifest do script này quản lý
            SKIP_MANIFEST_SCHEME_REWRITE: 'true',

            ANDROID_BUILD_TASK: a.buildTask,
            SEPARATE_APKS: bool(a.separateApks),
            UNIVERSAL_APK: bool(a.universalApk),
            SENTRY_PROJECT_ANDROID: s.projectAndroid,
            SENTRY_DSN_ANDROID: cfg.SentryDsnAndroid,
            SUPPLY_PACKAGE_NAME: (a.playStore || {}).packageName,
            SUPPLY_TRACK: (a.playStore || {}).track,
            SUPPLY_VALIDATE_ONLY: bool((a.playStore || {}).validateOnly),
        });
    } else {
        Object.assign(env, {
            APP_NAME: i.displayName,
            MAIN_APP_IDENTIFIER: i.bundleId,
            EXTENSION_APP_IDENTIFIER: i.shareExtensionBundleId,
            NOTIFICATION_SERVICE_IDENTIFIER: i.notificationServiceBundleId,
            IOS_APP_GROUP: i.appGroup,
            IOS_ICLOUD_CONTAINER: i.icloudContainer,
            IOS_KEYCHAIN_GROUP: i.keychainGroup,
            FASTLANE_TEAM_ID: i.teamId,
            IOS_BUILD_EXPORT_METHOD: i.exportMethod,
            MATCH_TYPE: i.matchType,
            MATCH_APP_IDENTIFIER: [i.notificationServiceBundleId, i.shareExtensionBundleId, i.bundleId].join(','),
            SYNC_PROVISIONING_PROFILES: bool(i.syncProvisioningProfiles),
            INTUNE_ENABLED: bool(i.intune && i.intune.enabled),
            SENTRY_PROJECT_IOS: s.projectIos,
            SENTRY_DSN_IOS: cfg.SentryDsnIos,
            FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT: 120,
            FASTLANE_XCODEBUILD_SETTINGS_RETRIES: 6,
        });
        if (i.intune && i.intune.enabled) {
            env.INTUNE_CLIENT_ID = i.intune.clientId;
        }
    }

    Object.assign(env, f.extraEnv || {});

    const lines = [
        '## TỰ SINH từ assets/base/config.json — ĐỪNG SỬA TAY.',
        '## Sinh lại: node scripts/build_config.js --apply',
        '',
    ];
    for (const [k, v] of Object.entries(env)) {
        if (v === undefined || v === null || v === '') {
            continue;
        }
        const str = String(v);
        lines.push(/[\s"'#]/.test(str) ? `${k}="${str}"` : `${k}=${str}`);
    }
    return `${lines.join('\n')}\n`;
}

function generatedEnvEdits(cfg) {
    const out = [];
    for (const [file, platform] of [[GEN_ENV_ANDROID, 'android'], [GEN_ENV_IOS, 'ios']]) {
        const wanted = fastlaneEnv(cfg, platform);
        const current = fileExists(file) ? readFile(file) : null;
        out.push({file, wanted, changed: current !== wanted});
    }
    return out;
}

// dist/assets/config.json (do scripts/generate-assets.js sinh) là file mà app
// thực sự đọc lúc chạy. Sửa config.json mà không sinh lại dist thì app vẫn dùng
// giá trị cũ, nên coi đây là một "chỗ lệch" cần cập nhật trước khi build.
const DIST_CONFIG = 'dist/assets/config.json';

function expectedDistConfig() {
    const base = JSON.parse(readFile('assets/base/config.json'));
    const overridePath = 'assets/override/config.json';
    const merged = fileExists(overridePath) ? Object.assign({}, base, JSON.parse(readFile(overridePath))) : base;
    return JSON.stringify(toAppConfig(merged));
}

function distConfigStale() {
    if (!fileExists(DIST_CONFIG)) {
        return true;
    }
    try {
        return readFile(DIST_CONFIG) !== expectedDistConfig();
    } catch (e) {
        return true;
    }
}

function regenerateAssets() {
    execFileSync(process.execPath, [path.join(ROOT, 'scripts/generate-assets.js')], {cwd: ROOT, stdio: 'pipe'});
}

// ------------------------------------------------------------------- lệnh
function changedEdits(edits) {
    return edits.filter((e) => !e.skip && !e.missing && e.current !== e.value);
}

function printSummary(cfg) {
    const b = cfg.Build;
    const line = (k, v) => console.log(`   ${DIM}${k.padEnd(22)}${RST}${v}`);
    const {auth, authDev} = authSchemes(cfg);

    console.log(`\n${BLD}  Ứng dụng${RST}`);
    line('Tên (Android)', b.App.name);
    line('Tên (iOS)', b.Ios.displayName);
    line('Phiên bản', `${b.App.version} (${b.App.buildNumber})`);
    line('URL scheme', `${b.App.scheme}, ${auth}, ${authDev}`);
    line('Môi trường', envLabel(cfg));
    line('Server mặc định', `${cfg.DefaultServerName || '-'} — ${cfg.DefaultServerUrl || '-'}`);

    console.log(`\n${BLD}  Android${RST}`);
    line('applicationId', b.Android.applicationId);
    line('package Java', b.Android.javaPackage);
    line('SDK', `min ${b.Android.minSdk} / target ${b.Android.targetSdk} / compile ${b.Android.compileSdk}`);
    line('NDK / buildTools', `${b.Android.ndk} / ${b.Android.buildTools}`);
    line('ABI', b.Android.architectures.join(', '));
    line('Cờ', `newArch ${b.Android.newArch} / hermes ${b.Android.hermes} / edgeToEdge ${b.Android.edgeToEdge}`);
    line('Task', `${b.Android.buildTask} / separateApks ${b.Android.separateApks} / universalApk ${b.Android.universalApk}`);
    line('Keystore', b.Android.signing.storeFile ? `${b.Android.signing.storeFile} (alias ${b.Android.signing.keyAlias})` : 'chưa cấu hình → dùng debug key');

    console.log(`\n${BLD}  iOS${RST}`);
    line('bundleId', b.Ios.bundleId);
    line('Share extension', b.Ios.shareExtensionBundleId);
    line('Notif service', b.Ios.notificationServiceBundleId);
    line('App group', b.Ios.appGroup);
    line('iCloud container', b.Ios.icloudContainer);
    line('Keychain group', b.Ios.keychainGroup);
    line('Team ID', b.Ios.teamId || '-');
    line('Push (aps-environment)', b.Ios.apsEnvironment);
    line('Xuất bản', `${b.Ios.exportMethod} / match ${b.Ios.matchType} / sync profiles ${b.Ios.syncProvisioningProfiles}`);
    line('Simulator', b.Ios.defaultSimulator || 'mặc định của Xcode');
    line('Intune', b.Ios.intune.enabled ? `bật (${b.Ios.intune.clientId})` : 'tắt');

    console.log(`\n${BLD}  Khác${RST}`);
    line('Sentry', cfg.SentryEnabled ? `bật / ${b.Sentry.org} / ${b.Sentry.projectIos},${b.Sentry.projectAndroid}` : 'tắt');
    line('Metro port', b.Dev.metroPort);
    line('Fastlane', `release ${b.Fastlane.buildForRelease} / beta ${b.Fastlane.betaBuild} / replaceAssets ${b.Fastlane.replaceAssets}`);

    if (cfg.__unresolved.length) {
        console.log(`\n${DIM}  Biến môi trường chưa đặt (coi như trống): ${cfg.__unresolved.join(', ')}${RST}`);
    }

    const edits = buildEdits(cfg);
    const pending = changedEdits(edits);
    const envs = generatedEnvEdits(cfg).filter((e) => e.changed);
    const stale = distConfigStale() ? 1 : 0;
    console.log('');
    if (pending.length === 0 && envs.length === 0 && stale === 0) {
        console.log(`  ${GRN}✓ project đang khớp với config.json${RST}`);
    } else {
        console.log(`  ${pending.length + envs.length + stale} chỗ trong project chưa khớp — chạy "--apply" để cập nhật.`);
    }
    for (const e of edits.filter((x) => x.skip)) {
        console.log(`  ${YLW}! ${e.file}: ${e.skip}${RST}`);
    }
    for (const e of edits.filter((x) => x.missing)) {
        console.log(`  ${YLW}! ${e.file}: không tìm thấy "${e.label}" để cập nhật${RST}`);
    }
}

function apply(cfg, dryRun) {
    const edits = buildEdits(cfg);
    const byFile = new Map();
    for (const e of changedEdits(edits)) {
        if (!byFile.has(e.file)) {
            byFile.set(e.file, []);
        }
        byFile.get(e.file).push(e);
    }

    let count = 0;
    for (const [file, list] of byFile) {
        if (!IS_MAC && file.startsWith('ios/')) {
            console.log(`  ${DIM}bỏ qua ${file} (chỉ áp dụng được trên macOS)${RST}`);
            continue;
        }
        let text = readFile(file);
        for (const e of list) {
            text = e.apply(text);
            console.log(`  ${dryRun ? '≠' : '✓'} ${file}  ${e.label}: ${e.current} → ${e.value}`);
            count++;
        }
        if (!dryRun) {
            fs.writeFileSync(path.join(ROOT, file), text);
        }
    }

    for (const e of generatedEnvEdits(cfg)) {
        if (!e.changed) {
            continue;
        }
        console.log(`  ${dryRun ? '≠' : '✓'} ${e.file}  (env Fastlane sinh từ config.json)`);
        count++;
        if (!dryRun) {
            fs.writeFileSync(path.join(ROOT, e.file), e.wanted);
        }
    }

    if (distConfigStale()) {
        console.log(`  ${dryRun ? '≠' : '✓'} ${DIST_CONFIG}  (sinh lại assets cho app đọc lúc chạy)`);
        count++;
        if (!dryRun) {
            regenerateAssets();
        }
    }

    for (const e of edits.filter((x) => x.skip)) {
        console.log(`  ${YLW}! ${e.file}: ${e.skip}${RST}`);
    }

    if (count === 0) {
        console.log(`  ${GRN}✓ project đã khớp config.json, không cần sửa gì${RST}`);
    } else if (dryRun) {
        console.log(`\n  ${YLW}${count} chỗ lệch so với config.json — chạy: node scripts/build_config.js --apply${RST}`);
    } else {
        console.log(`\n  ${GRN}✓ đã cập nhật ${count} chỗ theo config.json${RST}`);
    }
    return count;
}

function envLabel(cfg) {
    if (!cfg.__env) {
        return '-';
    }
    // eslint-disable-next-line no-process-env
    return process.env.TDC_ENV ? `${cfg.__env} (từ biến TDC_ENV)` : cfg.__env;
}

// Ghi Build.Environment vào config.json (giữ nguyên định dạng file)
function setEnvironment(name) {
    const raw = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    const envs = (raw.Build && raw.Build.Environments) || {};
    if (!name || !envs[name]) {
        fail(`môi trường "${name || ''}" không có trong Build.Environments (${Object.keys(envs).join(', ')})`);
    }
    const text = fs.readFileSync(CONFIG_FILE, 'utf8');
    const re = /("Environment"\s*:\s*)"[^"]*"/;
    if (!re.test(text)) {
        fail('thiếu "Build.Environment" trong assets/base/config.json');
    }
    fs.writeFileSync(CONFIG_FILE, text.replace(re, `$1"${name}"`));
    console.log(`  ${GRN}✓ môi trường: ${name} — ${envs[name].DefaultServerUrl}${RST}`);
}

// Xuất biến cho tdc.sh (bash eval được)
function gradleArgs(cfg) {
    const sign = cfg.Build.Android.signing;
    if (!sign.storeFile) {
        return [];
    }
    const abs = path.isAbsolute(sign.storeFile) ? sign.storeFile : path.join(ROOT, sign.storeFile);
    return [
        `-PMATTERMOST_RELEASE_STORE_FILE=${abs}`,
        `-PMATTERMOST_RELEASE_KEY_ALIAS=${sign.keyAlias}`,
        `-PMATTERMOST_RELEASE_PASSWORD=${sign.storePassword}`,
    ];
}

function printShell(cfg) {
    const b = cfg.Build;
    const q = (v) => `'${String(v).replace(/'/g, "'\\''")}'`;
    const out = [
        ['TDC_APP_NAME', b.App.name],
        ['TDC_IOS_APP_NAME', b.Ios.displayName],
        ['TDC_VERSION', b.App.version],
        ['TDC_BUILD_NUMBER', b.App.buildNumber],
        ['TDC_PKG', b.Android.applicationId],
        ['TDC_ACTIVITY', b.Android.mainActivity],
        ['TDC_METRO_PORT', b.Dev.metroPort],
        ['TDC_IOS_BUNDLE_ID', b.Ios.bundleId],
        ['TDC_IOS_SIMULATOR', b.Ios.defaultSimulator],
        ['TDC_ANDROID_BUILD_TASK', b.Android.buildTask],
        ['TDC_KEYSTORE', b.Android.signing.storeFile],
        ['TDC_SERVER_URL', cfg.DefaultServerUrl],
        ['TDC_ENV', cfg.__env],
        ['TDC_ENVS', Object.keys(b.Environments || {}).join(' ')],
    ];
    for (const [k, v] of out) {
        console.log(`${k}=${q(v)}`);
    }
    console.log(`TDC_GRADLE_ARGS=${q(gradleArgs(cfg).join(' '))}`);

    // Gradle đọc thêm các biến ORG_GRADLE_PROJECT_<tên> như property, nên truyền
    // thông tin ký qua môi trường thay vì -P (mật khẩu không hiện trong ps).
    const sign = cfg.Build.Android.signing;
    if (sign.storeFile) {
        const abs = path.isAbsolute(sign.storeFile) ? sign.storeFile : path.join(ROOT, sign.storeFile);
        console.log(`export ORG_GRADLE_PROJECT_MATTERMOST_RELEASE_STORE_FILE=${q(abs)}`);
        console.log(`export ORG_GRADLE_PROJECT_MATTERMOST_RELEASE_KEY_ALIAS=${q(sign.keyAlias)}`);
        console.log(`export ORG_GRADLE_PROJECT_MATTERMOST_RELEASE_PASSWORD=${q(sign.storePassword)}`);
    }
}

function main() {
    const args = process.argv.slice(2);
    if (args.includes('--env')) {
        setEnvironment(args[args.indexOf('--env') + 1]);
        return;
    }
    const cfg = loadConfig();
    validate(cfg);

    // Giá trị của môi trường đang chọn ghi đè lên cấu hình app (DefaultServerUrl...)
    if (cfg.__env) {
        Object.assign(cfg, cfg.Build.Environments[cfg.__env]);
    }

    if (args.includes('--envs')) {
        for (const [name, env] of Object.entries(cfg.Build.Environments || {})) {
            console.log(`${name === cfg.__env ? '*' : ' '} ${name.padEnd(8)} ${env.DefaultServerUrl}`);
        }
        return;
    }

    if (args.includes('--json')) {
        const copy = {...cfg};
        delete copy.__raw;
        delete copy.__unresolved;
        delete copy.__env;
        console.log(JSON.stringify(copy, null, 2));
        return;
    }
    if (args.includes('--shell')) {
        printShell(cfg);
        return;
    }
    if (args.includes('--gradle-args')) {
        console.log(gradleArgs(cfg).join(' '));
        return;
    }
    if (args.includes('--fastlane-env')) {
        const platform = args[args.indexOf('--fastlane-env') + 1] === 'ios' ? 'ios' : 'android';
        console.log(platform === 'ios' ? 'generated.ios' : 'generated.android');
        return;
    }
    if (args.includes('--apply')) {
        apply(cfg, false);
        return;
    }
    if (args.includes('--check')) {
        process.exit(apply(cfg, true) === 0 ? 0 : 1);
    }
    printSummary(cfg);
}

main();
