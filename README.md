<div align="center">

# TD Chat

**Ứng dụng chat nội bộ của Thái Dương — bản mobile, xây trên Mattermost Mobile v2**

[![React Native](https://img.shields.io/badge/React%20Native-0.83.9-61dafb?style=flat-square&logo=react)](https://reactnative.dev)
[![New Architecture](https://img.shields.io/badge/New%20Arch-enabled-8a2be2?style=flat-square)](https://reactnative.dev/architecture/landing-page)
[![Expo Router](https://img.shields.io/badge/Expo-55-000?style=flat-square&logo=expo)](https://docs.expo.dev/router/introduction/)
[![iOS](https://img.shields.io/badge/iOS-16.0%2B-black?style=flat-square&logo=apple)](#-yêu-cầu-môi-trường)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3ddc84?style=flat-square&logo=android)](#-yêu-cầu-môi-trường)

`com.thaiduongco.chat` · server tối thiểu **Mattermost 11.7.0+**

</div>

---

## Mục lục

| | |
|---|---|
| [1. Tổng quan](#1-tổng-quan) | [6. `tdc.sh` — bảng điều khiển](#6-tdcsh--bảng-điều-khiển-terminal) |
| [2. Yêu cầu môi trường](#2-yêu-cầu-môi-trường) | [7. Log gỡ lỗi TDCDBG](#7-log-gỡ-lỗi-tdcdbg) |
| [3. Cài đặt lần đầu](#3-cài-đặt-lần-đầu) | [8. Build & phát hành](#8-build--phát-hành) |
| [4. Bắt đầu trong 60 giây](#4-bắt-đầu-trong-60-giây) | [9. Kiểm tra trước khi commit](#9-kiểm-tra-trước-khi-commit) |
| [5. Cấu hình build](#5-cấu-hình-build--configjson-là-nguồn-duy-nhất) | [10. Lỗi hay gặp](#10-lỗi-hay-gặp) |

---

## 1. Tổng quan

Đây là bản fork nội bộ của [mattermost-mobile](https://github.com/mattermost/mattermost-mobile),
đóng gói thành ứng dụng riêng cho hệ thống `chat.thaiduongco.com`.

**Khác biệt so với bản gốc**

| Hạng mục | Nội dung |
|---|---|
| Thương hiệu | Tên app, icon, splash, theme màu riêng — sinh tự động từ `assets/base/images/tdc_logo.png` |
| Định danh | `com.thaiduongco.chat` (Android + iOS), App Group `group.com.thaiduongco.chat` |
| Cấu hình build | Gom về **một file duy nhất** `assets/base/config.json`, áp xuống native bằng `scripts/build_config.js` |
| Tiếng Việt | `assets/base/i18n/vi.json` được duy trì trực tiếp trong fork (không qua Weblate), có script đối chiếu với `en.json` |
| Công cụ dev | `tdc.sh` — bảng điều khiển terminal; `push_doctor.sh` — chẩn đoán push; log gỡ lỗi `TDCDBG` |
| Push notification | Firebase riêng (`android/app/google-services.json`) + Mattermost Push Proxy tự vận hành |

**Kiến trúc** (chi tiết trong [`CLAUDE.md`](CLAUDE.md))

```
app/
├── actions/        local/ (chỉ DB) · remote/ (API → operator → DB)
├── database/       WatermelonDB — 1 DB app + 1 DB cho mỗi server
├── queries/        query* (Query) · observe* (RxJS) · get* (Promise) · prepare* (batch)
├── products/       agents · boards · calls · playbooks (mỗi product tự chứa đủ tầng)
├── routes/         expo-router — file re-export mỏng, code màn hình nằm ở app/screens/
└── screens/        UI
libraries/@mattermost/   native module tự viết (rnutils, rnshare, secure-pdf-viewer…)
share_extension/         bundle riêng cho Share trên Android (iOS dùng Swift native)
scripts/                 build_config.js · gen_icons.py · push_doctor.sh · i18n_check.py · trace_viewer.mjs
tdc.sh                   bảng điều khiển terminal
```

**Tài liệu liên quan**

| File | Nội dung |
|---|---|
| [`RUNNING.md`](RUNNING.md) | Cẩm nang đầy đủ: chạy app, bắt API, đọc log, push notification, branding, i18n, lỗi build |
| [`CLAUDE.md`](CLAUDE.md) | Quy ước kiến trúc & code style của dự án |
| [`CLAUDE-IOS-SIMULATOR.md`](CLAUDE-IOS-SIMULATOR.md) | Dựng iOS simulator, xử lý sự cố CocoaPods |
| [`docs/testing_guide.md`](docs/testing_guide.md) | Cách viết và tổ chức unit test |

---

## 2. Yêu cầu môi trường

| Công cụ | Phiên bản | Kiểm tra |
|---|---|---|
| Node | **24.15.0** (`.nvmrc`) | `node -v` |
| npm | ^10 \|\| ^11 | `npm -v` |
| Ruby | **3.2.11** (`.ruby-version`) | `ruby -v` |
| Java | 17 | `java -version` |
| Xcode | mới nhất + Command Line Tools | `xcodebuild -version` |
| Android SDK | compileSdk 36, NDK 27.1.12297006 | `adb version` |
| Watchman | bất kỳ | `watchman -v` |

```bash
nvm use                 # đọc .nvmrc
rbenv local 3.2.11      # hoặc rvm use 3.2.11
./tdc.sh doctor         # in toàn bộ phiên bản đang có + thiếu gì
```

---

## 3. Cài đặt lần đầu

```bash
npm install             # kèm preinstall/postinstall: patch-package + scripts/postinstall.sh
npm run ios-gems        # bundle install (Fastlane, CocoaPods)
npm run pod-install     # cd ios && RCT_NEW_ARCH_ENABLED=1 pod install
```

Android cần thêm `android/local.properties`:

```properties
sdk.dir=/Users/<ten-may>/Library/Android/sdk
```

---

## 4. Bắt đầu trong 60 giây

```bash
./tdc.sh
```

Chọn **Chạy & Debug → Android: build + cài đặt + mở + log gỡ lỗi**. Xong.

Chưa bật máy ảo cũng không sao: script phát hiện không có thiết bị và hỏi
`Khởi động máy ảo ngay? [Y/n]` — Enter là bật rồi chạy tiếp việc đang làm.

Hoặc làm thủ công:

```bash
npm start                                  # terminal A — Metro
adb reverse tcp:8081 tcp:8081              # terminal B
npm run android
```

---

## 5. Cấu hình build — `config.json` là nguồn duy nhất

Mọi thứ liên quan tới build nằm ở khối `"Build"` trong **`assets/base/config.json`**:
tên app, version, build number, applicationId, bundle ID, App Group, Team ID, SDK/NDK,
kiến trúc CPU, thông tin ký, cấu hình Play Store.

> **Không sửa tay** `build.gradle`, `AndroidManifest.xml`, `Info.plist`, `project.pbxproj`.
> Sửa `config.json` rồi áp dụng — `scripts/build_config.js` ghi xuống tất cả file native
> và sinh env cho Fastlane (`fastlane/.env.generated.*`).

```bash
./tdc.sh config          # xem toàn bộ cấu hình đang khai báo
./tdc.sh config-check    # đối chiếu project với config.json (lệch → exit 1, dùng cho CI)
./tdc.sh config-apply    # ghi cấu hình xuống native + sinh env Fastlane
```

Mọi lệnh build/chạy trong `tdc.sh` đều tự gọi `config-apply` trước, nên bình thường
bạn chỉ cần sửa `config.json` rồi build.

Giá trị dạng `${TÊN_BIẾN}` (ví dụ mật khẩu keystore) được lấy từ biến môi trường lúc build —
khoá ký **không** nằm trong repo.

---

## 6. `tdc.sh` — bảng điều khiển terminal

Một file bash duy nhất ở gốc dự án, gom toàn bộ việc hằng ngày vào một menu.
**Không cần cài thêm gì** — bash thuần, không dùng `dialog`/`whiptail`/npm package,
chạy được trên bash 3.2 mặc định của macOS.

```bash
./tdc.sh                    # mở giao diện
./tdc.sh <lệnh> [tham số]   # chạy thẳng, không qua giao diện
```

### 6.1 Giao diện

```
  TD Chat  v1.0.0 (1)  release-2.44
  Metro đang chạy  emulator-5554  đã reverse
  ────────────────────────────────────────────────────────────

  Chọn việc cần làm

   1  Chạy & Debug
   2  Build  (APK / AAB / IPA)
   3  Kiểm tra  (lint / tsc / test)
   4  Thiết bị & Log
   5  Cấu hình build  (assets/base/config.json)
   6  Công cụ dự án
      ······························
   7  Thoát — đóng bảng điều khiển  (q)

  mũi lên/xuống hoặc k/j · Enter để chọn · phím tắt bên trái · q quay lại
```

**Thanh trạng thái** (2 dòng trên cùng) — tính lại mỗi khi vào menu hoặc chạy xong một lệnh:

| Thành phần | Ý nghĩa |
|---|---|
| `TD Chat v1.0.0 (1)` | Tên app, version, build number — đọc từ `config.json` |
| `release-2.44` | Nhánh git hiện tại |
| `Metro đang chạy` / `Metro tắt` | Có tiến trình nào giữ cổng 8081 không |
| `emulator-5554` | Các thiết bị `adb` đang kết nối |
| `đã reverse` / `chưa reverse` | `adb reverse tcp:8081` đã thiết lập chưa |
| `config.json: …` (đỏ) | Cấu hình build đang lỗi — cần sửa trước khi build |

**Điều hướng**

| Phím | Tác dụng |
|---|---|
| `↑` `↓` hoặc `k` `j` | Di chuyển (tự nhảy qua dòng phân cách, chạy vòng đầu–cuối) |
| `Enter` | Chọn mục đang sáng |
| `1`–`9`, rồi `a` `b` `c`… | Phím tắt — chọn thẳng mục tương ứng ở cột trái |
| `q` hoặc `Esc` | Quay lại trang trước (ở menu chính là thoát) |
| `Ctrl+C` | Dừng lệnh đang chạy (build, log, test…) và quay về menu |

Sau khi một lệnh chạy xong, màn hình hiện `✓ xong trong Ns` hoặc `✗ thất bại (exit N)`
rồi chờ `Enter`/`q` để quay lại — không bị trôi mất output.

### 6.2 Menu **Chạy & Debug**

| # | Mục | Việc thật sự chạy |
|---|---|---|
| 1 | Khởi động Metro ở cửa sổ Terminal mới | `osascript` mở Terminal mới chạy `npm start` (chỉ macOS) — log JS ở cửa sổ đó, bấm `j` để mở React Native DevTools |
| 2 | Metro ở cửa sổ này (xoá cache) | `npm start -- --reset-cache` |
| 3 | Tắt Metro (port 8081) | `lsof -ti:8081 \| xargs kill -9` |
| 4 | **Android: khởi động máy ảo…** | Chọn AVD (một cái thì bật luôn), chờ `sys.boot_completed` rồi gạt màn hình khoá — chỉ chờ đúng máy vừa bật, không nhầm với máy đang cắm |
| 5 | Android: build + cài đặt + mở | `adb reverse` rồi `npm run android -- --deviceId=<thiết bị>` |
| 6 | **Android: build + cài + mở + log gỡ lỗi** | Như trên, build xong xoá buffer logcat rồi mở thẳng bộ xem log `TDCDBG` — mục dùng nhiều nhất |
| 7 | Android: chỉ mở app (không build) | `adb shell am start -n com.thaiduongco.chat/…MainActivity` |
| 8 | Android: xem log gỡ lỗi | Bộ xem gập/mở cho app đang chạy — xem [mục 7](#7-log-gỡ-lỗi-tdcdbg) |
| 9 | Android: log gỡ lỗi dạng text | Xả thẳng ra terminal, không giao diện (`TDC_TRACE_PLAIN=1`) |
| a | Android: adb reverse 8081 | Mở đường cho thiết bị gọi về Metro trên máy |
| b | Android: mở dev menu | `adb shell input keyevent 82` |
| c | **Android: bắt HTTPS qua Proxyman/Charles** | Hỏi địa chỉ proxy (mặc định `10.0.2.2:9090`), ghi vào `settings global http_proxy`, force-stop app |
| d | Android: tắt proxy | Đặt lại `http_proxy :0` |
| e | iOS: mở simulator… | `xcrun simctl boot` + `open -a Simulator` |
| f | iOS: chạy trên simulator mặc định | `npm run ios` (dùng `Build.Ios.defaultSimulator` nếu có khai trong `config.json`) |
| g | iOS: chọn simulator rồi chạy | Liệt kê simulator khả dụng từ `xcrun simctl` |
| h | iOS: chạy trên thiết bị thật | `npm run ios -- --device` |
| i | iOS: xem log gỡ lỗi (simulator) | `xcrun simctl spawn booted log stream` lọc `TDCDBG` |

> Có nhiều thiết bị thì script hỏi chọn; chỉ có một thì dùng luôn.
> **Không có thiết bị nào** thì hỏi `Khởi động máy ảo ngay? [Y/n]` rồi bật giúp, xong chạy tiếp.
> Các mục Android build/mở app tự chạy `adb reverse` giúp.

### 6.3 Menu **Build**

| # | Mục | Lệnh tương đương | Dùng khi |
|---|---|---|---|
| 1 | APK debug | `gradlew app:assembleDebug` | Test nội bộ, cần Metro |
| 2 | APK release | `gradlew app:assembleRelease` | Bản chạy độc lập, có ký |
| 3 | **AAB release** | `gradlew app:bundleRelease` | **Tải lên Play Store** |
| 4 | APK release chỉ `arm64-v8a` | `-PreactNativeArchitectures=arm64-v8a` | Nhanh ~3×, đủ cho máy thật |
| 5 | APK debug chỉ `arm64-v8a` | như trên, bản debug | Vòng lặp build nhanh |
| 6 | APK qua Fastlane | `npm run build:android` | Quy trình phát hành chuẩn |
| 7 | APK chưa ký | `npm run build:android-unsigned` | Gửi bên khác tự ký |
| 8 | AAB qua Fastlane | `ANDROID_BUILD_TASK=bundle npm run build:android` | Phát hành Play Store |
| 9 | iOS cho simulator | `npm run build:ios-sim` | Kiểm thử trên máy Mac |
| a | IPA | `npm run build:ios` | Phát hành iOS |
| b | IPA chưa ký | `npm run build:ios-unsigned` | Ký ở nơi khác |
| c | Xem các file đã build | Liệt kê `.apk`/`.aab`/`.ipa` kèm dung lượng và thời điểm | Tìm lại file vừa build |

Build xong, script tự in đường dẫn + dung lượng file mới tạo, kèm sẵn lệnh cài:

```
  ✓ xong trong 214s

  File vừa tạo:
      82M  app-release.apk
           /Users/…/android/app/build/outputs/apk/release/app-release.apk

  Cài lên máy:  adb install -r "/Users/…/app-release.apk"
```

### 6.4 Menu **Kiểm tra**

| # | Mục | Lệnh |
|---|---|---|
| 1 | **check** — chạy trước khi commit | `npm run check` (lint + tsc) |
| 2 | check-test | `npm run check-test` (lint + tsc + jest) |
| 3 | lint | `npm run lint` |
| 4 | fix | `npm run fix` (eslint --fix) |
| 5 | tsc | `npm run tsc` |
| 6 | test — toàn bộ | `npm test` |
| 7 | test theo pattern… | Nhập đường dẫn file hoặc từ khoá, ví dụ `edit_profile` |
| 8 | test:watch | `npm run test:watch` |
| 9 | test:coverage | `npm run test:coverage` |
| a | i18n check | `python3 scripts/i18n_check.py` — đối chiếu `vi.json` với `en.json` (thiếu key, lệch placeholder) |

### 6.5 Menu **Thiết bị & Log**

| # | Mục | Ghi chú |
|---|---|---|
| 1 | Danh sách thiết bị | `adb devices -l` |
| 2 | Danh sách AVD | `emulator -list-avds` |
| 3 | **Khởi động máy ảo…** | Bật AVD rồi chờ Android khởi động xong |
| 4 | **Log gỡ lỗi TDC** | Màn hình + API + WebSocket, gập/mở từng mục — xem [mục 7](#7-log-gỡ-lỗi-tdcdbg) |
| 5 | Log JS | `adb logcat *:S ReactNativeJS:V` |
| 6 | Log toàn bộ app | Theo `pid` của app — gồm cả log native |
| 7 | Log push notification | Lọc `CustomPushNotification`, `ReactNativeNotifs`, token… |
| 8 | 200 dòng gần nhất rồi thoát | Dump nhanh, không bám theo |
| 9 | Xoá buffer logcat | `adb logcat -c` — làm sạch trước khi tái hiện lỗi |
| a | Log iOS simulator | `npx react-native log-ios` |
| b | Chụp ảnh màn hình | Lưu `screenshot-YYYYmmdd-HHMMSS.png` ở gốc dự án |
| c | Buộc dừng app | `adb shell am force-stop` |
| d | **Gỡ app** | ⚠️ Mất session đăng nhập + toàn bộ DB trên máy — phải gõ `go` để xác nhận |

### 6.6 Menu **Cấu hình build**

| # | Mục | Lệnh |
|---|---|---|
| 1 | Xem toàn bộ cấu hình | `node scripts/build_config.js` |
| 2 | Kiểm tra project có khớp cấu hình | `--check` (lệch → exit 1) |
| 3 | Áp dụng xuống project + env Fastlane | `--apply` |
| 4 | Mở `config.json` để sửa | Dùng `$VISUAL`/`$EDITOR`, không có thì `nano`/`vi`; sửa xong tự áp dụng lại |

### 6.7 Menu **Công cụ dự án**

| # | Mục | Ghi chú |
|---|---|---|
| 1 | Thông tin môi trường | node/npm/ruby/java/xcodebuild/adb/pod + nhánh git, số file thay đổi, đã có `node_modules`/`Pods` chưa, Firebase project id |
| 2 | **Sửa lỗi build CXX1409** | Xoá `android/app/.cxx` — xem [mục 10](#10-lỗi-hay-gặp) |
| 3 | Chẩn đoán push notification | `./scripts/push_doctor.sh` |
| 4 | Sinh lại icon từ `images/tdc_logo.png` | `python3 scripts/gen_icons.py` — sinh đủ mọi mật độ Android + iOS |
| 5 | Sinh lại splash bản release | `python3 scripts/gen_release_splash.py` |
| 6 | Đồng bộ `assets/base` → `dist/assets` | `node scripts/generate-assets.js` |
| 7 | npm install | |
| 8 | pod install | `npm run pod-install` |
| 9 | clean | `npm run clean` |
| a | **Reset sâu** | clean + xoá `node_modules`, `ios/Pods`, cache Metro/watchman rồi `npm install` — gõ `reset` để xác nhận |
| b | i18n-extract | Sinh lại `en.json` từ `defineMessages()` trong code |

### 6.8 Gọi trực tiếp (không qua giao diện)

Tiện cho CI, script, hoặc khi đã biết mình cần gì:

```bash
# Build
./tdc.sh apk               # APK debug   (gradlew assembleDebug)
./tdc.sh apk-release       # APK release (gradlew assembleRelease)
./tdc.sh apk-arm64         # APK release chỉ arm64-v8a — nhanh ~3×, đủ cho máy thật
./tdc.sh aab               # AAB release (gradlew bundleRelease)
./tdc.sh ipa               # IPA qua Fastlane
./tdc.sh ios-sim           # build iOS cho simulator
./tdc.sh artifacts         # liệt kê các file .apk/.aab/.ipa đã build

# Máy ảo / simulator
./tdc.sh emulator          # bật máy ảo Android rồi chờ khởi động xong
./tdc.sh emulator Pixel_9_Pro   # chỉ đích danh AVD
./tdc.sh avds              # liệt kê máy ảo đã tạo
./tdc.sh simulator         # mở iOS simulator

# Chạy
./tdc.sh android           # build + cài đặt + mở trên Android
./tdc.sh ios               # chạy trên iOS simulator
./tdc.sh metro             # Metro (xoá cache)
./tdc.sh android-log       # build + cài + mở + bám log gỡ lỗi

# Log & bắt API
./tdc.sh trace             # bộ xem log gập/mở: màn hình + API + WebSocket (Android)
./tdc.sh trace-text        # như trên nhưng xả thẳng ra terminal
./tdc.sh trace-ios         # bộ xem log trên iOS simulator
./tdc.sh proxy 10.0.2.2:9090   # trỏ máy ảo qua Proxyman/Charles
./tdc.sh proxy off         # tắt proxy
./tdc.sh log               # log JS
./tdc.sh log-push          # log push notification

# Kiểm tra & cấu hình
./tdc.sh check             # lint + tsc
./tdc.sh test              # jest
./tdc.sh config            # xem cấu hình build
./tdc.sh config-apply      # áp dụng cấu hình xuống project
./tdc.sh config-check      # đối chiếu, lệch thì exit 1  ← dùng trong CI

# Chẩn đoán
./tdc.sh doctor            # thông tin môi trường
./tdc.sh push-doctor       # chẩn đoán push notification
./tdc.sh fix-cxx           # xoá metadata CMake khi gặp lỗi CXX1409
./tdc.sh help
```

Biến môi trường:

| Biến | Tác dụng |
|---|---|
| `TDC_TRACE_PLAIN=1` | Log gỡ lỗi xả thẳng ra terminal thay vì mở bộ xem gập/mở |
| `TDC_TRACE_SHORT=1` | Ở chế độ text: ẩn header/body, chỉ giữ dòng tóm tắt |
| `MATTERMOST_RELEASE_PASSWORD` | Mật khẩu keystore khi build release có ký |
| `ANDROID_BUILD_TASK=bundle` | Ép lane Fastlane Android build AAB thay vì APK |

### 6.9 Ghi chú kỹ thuật

- Script tự thêm `platform-tools` và `emulator` vào `PATH` khi tìm thấy Android SDK — không cần `export PATH` trước.
- Tự chuyển sang locale UTF-8 nếu terminal chưa dùng, để nhãn tiếng Việt canh lề đúng.
- Terminal được đặt sang chế độ **cbreak** trong lúc hiện menu và **trả về nguyên trạng trước khi chạy bất kỳ lệnh nào** — `Ctrl+C` vẫn dừng được build, thoát ra shell không bị hỏng.
- Phím đọc bằng `dd` thay vì `read -sn1`: trên macOS `read -sn1` gọi `tcsetattr` mỗi lần đọc và làm mất byte còn lại trong bộ đệm, khiến phím mũi tên (3 byte `ESC [ A`) không bao giờ đọc đủ.
- Không chớp khi bấm mũi: dùng `\033[H` + `\033[K` từng dòng thay cho `\033[2J`, và mỗi lần bấm chỉ vẽ lại **2 dòng** (dòng cũ + dòng mới).
- Thanh trạng thái gọi `lsof`/`adb`/`git` nên chỉ tính lại khi vào menu hoặc sau khi chạy xong lệnh, không tính mỗi lần bấm phím.

---

## 7. Log gỡ lỗi TDCDBG

Bản debug in ra các dòng có tiền tố `TDCDBG` (`app/utils/dev_trace.ts`) cho ba nhóm sự kiện,
kèm header + body đầy đủ của từng request:

| Nhóm | Màu | Nội dung | Móc vào |
|---|---|---|---|
| `NAV` | xanh dương | Màn hình đang mở / chuyển màn hình | `app/store/navigation_store.ts` |
| `API` | xanh lá (2xx/3xx) · đỏ (4xx/5xx) | Method, đường dẫn, status, thời gian, dung lượng | `app/client/rest/tracking.ts` |
| `WS` | vàng | Sự kiện WebSocket (open/close/event) | `app/client/websocket/index.ts` |
| `req.*` `res.*` `ws.data` | xám | Header + body của request/response và payload WebSocket | — |

### 7.1 Bộ xem log — gập/mở từng mục

`./tdc.sh trace` mở `scripts/trace_viewer.mjs`: gom từng request thành một dòng, bấm mở ra
mới xem chi tiết, JSON tự xuống dòng thụt lề. Chạy bằng Node có sẵn, không thêm dependency.

```
  TDC trace  128/128 mục  ·  lọc: API  ·  bám đuôi
▸ API  GET    200   154ms   /api/v4/channels/33o9.../posts?since=1789800240746
▾ API  PUT    200   713ms   /api/v4/users/sessions/device  [Cold Start]
    req.headers Authorization: BEARER ng4h59pk4fre8eq1w7q45zwg1c, Accept: application/json
    res.body {
               "first_inaccessible_post_time": 0,
               "posts": {},
               "order": []
```

| Phím | Tác dụng |
|---|---|
| `↑` `↓` hoặc `k` `j` | Chọn mục |
| `Enter` | Mở / gập mục đang chọn (`▸` ↔ `▾`) |
| `e` / `c` | Mở tất cả / gập tất cả |
| `f` | Lọc theo loại: tất cả → API → WS → NAV |
| `/` | Tìm trong cả dòng tóm tắt lẫn nội dung chi tiết |
| `g` / `G` | Về đầu / về cuối (bật lại bám đuôi) |
| `p` | Tạm dừng bám đuôi (tự dừng khi bạn di chuyển lên) |
| `x` | Xoá sạch danh sách |
| `q` | Thoát |

```bash
./tdc.sh trace                      # bám log của app đang chạy
./tdc.sh android-log                # build + cài + mở rồi mở bộ xem luôn
./tdc.sh trace-ios                  # iOS simulator
./tdc.sh trace-text                 # xả thẳng ra terminal, không giao diện
TDC_TRACE_SHORT=1 ./tdc.sh trace-text   # text, chỉ dòng tóm tắt
```

Pipe ra file thì bộ xem tự chuyển sang in thẳng, không dựng giao diện:
`./tdc.sh trace > trace.log`.

### 7.2 Bật/tắt từng nhóm

Trong console của React Native DevTools (bấm `j` ở cửa sổ Metro):

```js
tdcTrace({api: false})        // tắt log API
tdcTrace({ws: false})         // tắt log WebSocket
tdcTrace({headers: false})    // bỏ phần header
tdcTrace({body: false})       // bỏ phần body
tdcTrace({apiRequest: true})  // in thêm lúc request vừa gửi đi — soi request treo
tdcTrace({bodyLimit: 20000})  // body dài hơn (mặc định 4000 ký tự)
```

### 7.3 Lưu ý bảo mật

Log in **nguyên văn** token, cookie và nội dung request/response — tiện gỡ lỗi nhưng
đừng dán nguyên ra ngoài. Toàn bộ phần này chỉ chạy khi `__DEV__`, và `index.tsx` đặt
`logToFile: !__DEV__` nên bản debug không ghi log xuống file người dùng xuất được,
cũng không đẩy lên Sentry. Bản release không sinh dòng `TDCDBG` nào.

### 7.4 Xem dạng GUI — Proxyman / Charles

Cần cây request kiểu Network tab (gập từng header, sửa và gửi lại request) thì trỏ máy ảo
qua proxy. App tin cả CA do người dùng cài (`android/app/src/main/res/xml/network_security_config.xml`)
nên không phải sửa gì trong code:

```bash
./tdc.sh proxy                 # mặc định 10.0.2.2:9090 (Proxyman)
./tdc.sh proxy 10.0.2.2:8888   # Charles
./tdc.sh proxy off
```

Lần đầu nhớ cài chứng chỉ CA của Proxyman/Charles vào máy ảo (Proxyman:
Certificate → Install on Android Emulator). Lệnh này tự force-stop app, mở lại là có traffic.

> React Native DevTools (bấm `j` ở Metro) có Components + Profiler nhưng **tab Network luôn
> trống**: app gọi mạng qua `@mattermost/react-native-network-client` (native), không qua
> `fetch`/XHR. Đó là lý do có `TDCDBG` và đường proxy ở trên.

---

## 8. Build & phát hành

```bash
./tdc.sh config-apply      # 1. áp cấu hình (version, build number, ký…) xuống native
./tdc.sh aab               # 2. AAB cho Play Store
./tdc.sh ipa               # 3. IPA cho App Store / TestFlight
```

Tăng version hoặc build number: sửa `App.version` / `App.buildNumber` trong
`assets/base/config.json` rồi `./tdc.sh config-apply`.

> **Lưu ý:** tự build app thì phải tự vận hành
> [Mattermost Push Notification Service](https://github.com/mattermost/mattermost-push-proxy/releases).
> App **không** kết nối được với server dùng chứng chỉ tự ký.

---

## 9. Kiểm tra trước khi commit

```bash
./tdc.sh check        # lint + tsc  — bắt buộc
npm run check-test    # kèm jest
npm test -- app/queries/servers/channel.test.ts    # một file
npm test -- -t 'should return the channel'         # một test
```

Husky pre-commit tự chạy ESLint + tsc tăng dần. Quy ước code, cách viết test, quy tắc
i18n và những lỗi hay mắc: xem [`CLAUDE.md`](CLAUDE.md).

---

## 10. Lỗi hay gặp

<details>
<summary><b><code>INSTALL_FAILED_VERSION_DOWNGRADE</code> — "Update version code 1 is older than current 815"</b></summary>

Máy đang cài bản có build number cao hơn bản sắp cài (thường là bản release cũ vs bản debug mới).

```bash
adb uninstall com.thaiduongco.chat
npm run android
```
</details>

<details>
<summary><b><code>[CXX1409] expected buildFiles file '.../codegen/jni/CMakeLists.txt' to exist</code></b></summary>

Gradle lưu đường dẫn tuyệt đối tới file CMake do codegen sinh trong `node_modules`.
Xoá `node_modules` rồi cài lại mà `.cxx` còn nguyên thì build gãy.

```bash
./tdc.sh fix-cxx        # xoá android/app/.cxx
```
</details>

<details>
<summary><b>Metro chạy nhưng app báo không tải được bundle</b></summary>

Thiếu `adb reverse`:

```bash
./tdc.sh   →  Chạy & Debug  →  Android: adb reverse 8081
```
</details>

<details>
<summary><b>Không nhận được push notification</b></summary>

```bash
./tdc.sh push-doctor
```

Script kiểm tra lần lượt: token thiết bị, cấu hình Firebase, khả năng nhận của server,
và push proxy. Phân tích chi tiết từng tầng nằm ở [`RUNNING.md` mục 13](RUNNING.md).
</details>

<details>
<summary><b>Build gãy lạ sau khi đổi nhánh / cài lại package</b></summary>

```bash
./tdc.sh   →  Công cụ dự án  →  Reset sâu
```

Xoá `node_modules`, `ios/Pods`, cache Metro và watchman rồi cài lại.
</details>

---

<div align="center">
<sub>

Dựa trên [Mattermost Mobile](https://github.com/mattermost/mattermost-mobile) — xem [`LICENSE.txt`](LICENSE.txt) và [`NOTICE.txt`](NOTICE.txt).

</sub>
</div>
