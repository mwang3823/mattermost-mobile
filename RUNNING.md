# Running the App & Debugging API

> **Cách nhanh nhất: `./tdc.sh`** — bảng điều khiển terminal gói sẵn mọi thứ trong tài liệu
> này (chạy, build APK/AAB/IPA, log, kiểm tra, chẩn đoán push). Xem [mục 14](#14-tdcsh--bảng-điều-khiển-terminal).
> Các mục bên dưới là lệnh thủ công tương ứng.

## 1. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Node | 24.15.0 (`.nvmrc`) | `node -v` |
| npm | ^10 \|\| ^11 | `npm -v` |
| Ruby | 3.2.11 (`.ruby-version`) | `ruby -v` |
| Xcode | latest + Command Line Tools | `xcodebuild -version` |
| Java | 17 (Android) | `java -version` |
| Watchman | any | `watchman -v` |

```bash
nvm use                 # reads .nvmrc
rbenv local 3.2.11      # or: rvm use 3.2.11
```

## 2. First-time Setup

```bash
npm install             # runs preinstall/postinstall (patch-package + scripts/postinstall.sh)
npm run ios-gems        # bundle install (Fastlane, CocoaPods)
npm run pod-install     # cd ios && RCT_NEW_ARCH_ENABLED=1 pod install
```

Android extra: create `android/local.properties` with `sdk.dir=/Users/<you>/Library/Android/sdk`
(or export `ANDROID_HOME`). Firebase config lives at `android/app/google-services.json`.

## 3. Chạy app

### 3.1 Quy trình chuẩn — 2 terminal

Luôn mở **Metro trước** ở terminal riêng, rồi mới mở app ở terminal thứ hai.
Làm ngược lại (`npm run android` trước) thì CLI tự spawn Metro ở tiến trình nền —
bundle vẫn chạy nhưng **stdout không hiện ở đâu cả**, mất log và không nhấn được `j`.

**Terminal A — Metro (để mở suốt, đây là nơi xem log & mở DevTools)**

```bash
cd /Users/mwang/Projects/TDC/mattermost-mobile
npm start
```

**Terminal B — mở app**

```bash
export PATH=$PATH:~/Library/Android/sdk/platform-tools

adb reverse tcp:8081 tcp:8081                  # bắt buộc, xem 3.3
adb shell monkey -p com.thaiduongco.chat 1     # mở app đã cài sẵn
```

Xong: log JS chạy ở **Terminal A**, nhấn `j` ở đó để mở React Native DevTools.

### 3.2 Khi nào cần build lại

`adb shell monkey ...` chỉ **mở app đã cài** — nhanh, không build. Chỉ chạy
`npm run android` khi thực sự cần build lại:

| Thay đổi | Cần làm gì |
|---|---|
| Sửa `.ts` / `.tsx` | Không làm gì — Metro hot reload (~3s) |
| Thêm/xoá package JS | Restart Metro: `npm start -- --reset-cache` |
| Sửa native (Kotlin/Java/Obj-C), `AndroidManifest.xml`, `build.gradle`, `google-services.json` | `npm run android` (build lại, 1–30 phút) |
| Chưa cài app lần nào | `npm run android` |

```bash
npm run android                              # build + install + mở app
npm run android -- --deviceId=emulator-5554  # chỉ định thiết bị khi có nhiều máy
npm run android -- --mode=release            # build release
```

> `npm run android` **chỉ build + install rồi thoát** — nó không stream log.
> Log vẫn nằm ở Terminal A (Metro) hoặc `adb logcat`.

### 3.3 adb reverse — bắt buộc cho Android

`npm start` chạy với `--host 127.0.0.1`, nên emulator/thiết bị phải đi qua `adb reverse`:

```bash
adb reverse tcp:8081 tcp:8081
adb reverse --list                # kiểm tra: host-xx tcp:8081 tcp:8081
```

Bị mất khi Metro chết, adb server restart, hoặc rút/cắm lại thiết bị.
Nếu app báo **"Cannot connect to Metro — URL: 10.0.2.2:8081"** → chạy lại lệnh trên
rồi reload app (nhấn `R` hai lần, hoặc `r` ở Terminal A).

### 3.4 Lệnh Android hay dùng

```bash
export PATH=$PATH:~/Library/Android/sdk/platform-tools     # thêm vào ~/.zshrc cho tiện

adb devices                                  # liệt kê thiết bị: emulator-5554  device
emulator -list-avds                          # liệt kê AVD
emulator -avd <ten-avd> &                    # khởi động emulator
```

Package id của app: **`com.thaiduongco.chat`** (debug không có suffix).

```bash
adb shell monkey -p com.thaiduongco.chat 1          # mở app
adb shell pidof -s com.thaiduongco.chat             # app đang chạy chưa
adb shell am force-stop com.thaiduongco.chat        # kill app
adb uninstall com.thaiduongco.chat                  # gỡ để cài sạch (mất session + DB)
```

### 3.5 iOS

```bash
xcrun simctl list devices available          # liệt kê simulator
xcrun simctl boot "iPhone 16 Pro"

npm run ios
npm run ios -- --simulator="iPhone 16 Pro"
npm run ios -- --device                      # thiết bị thật
npm run ios -- --mode=Release
```

iOS không cần `adb reverse` — simulator dùng chung loopback với máy Mac.

### 3.6 Metro

Phím tắt trong terminal đang chạy `npm start`:

| Phím | Tác dụng |
|---|---|
| `r` | Reload app |
| `d` | Mở dev menu trên thiết bị |
| **`j`** | **Mở React Native DevTools** |

```bash
npm start                                    # chạy Metro
npm start -- --reset-cache                   # khi bundle bị stale
```

Kiểm tra app đã gắn vào Metro chưa (điều kiện để `j` hoạt động):

```bash
curl -s http://127.0.0.1:8081/json/list
```

Trả về `[]` = app chưa kết nối → kiểm tra `adb reverse` rồi reload app.
Trả về 1 target (`React Native Bridgeless [C++ connection]`) = sẵn sàng nhấn `j`.

#### Lỗi "A dev server is already running for this project on port 8081. Exiting."

Đã có một Metro khác giữ port 8081 — thường do `npm run android` / `npm run ios` tự spawn
Metro ở tiến trình nền, hoặc do một cửa sổ terminal cũ đã đóng. Metro đó vẫn phục vụ bundle
bình thường, **nhưng stdout không hiển thị ở đâu cả** → mất log, không nhấn được `j`.

Kill nó rồi tự chạy lại:

```bash
lsof -nP -iTCP:8081 -sTCP:LISTEN     # xem tiến trình nào đang giữ port
lsof -ti:8081 | xargs kill -9        # kill nó
```

Rồi **chạy riêng** lệnh tiếp theo:

```bash
npm start
```

> ⚠️ Dán nhiều lệnh một lúc vào zsh sẽ chạy **tuần tự theo thứ tự dán**. Nếu dán cả
> `npm start` lẫn `lsof ... | xargs kill -9` thì `npm start` chạy trước lệnh kill và
> vẫn báo lỗi. Kill xong mới chạy `npm start`.

### 3.7 Dev menu & reload trên thiết bị

| | iOS Simulator | Android |
|---|---|---|
| Dev menu | `Cmd+D` | `Cmd+M` hoặc `adb shell input keyevent 82` |
| Reload | `Cmd+R` | nhấn `R` hai lần |
| Reload | `Cmd+R` | nhấn `R` hai lần |
## 4. Checks & Tests

```bash
npm run check           # lint + tsc  (run before every commit)
npm run check-test      # lint + tsc + jest
npm run fix             # eslint --fix
npm test -- app/queries/servers/channel.test.ts
npm test -- -t 'should return the channel'
npm run test:watch
npm run updatesnapshot
```

## 5. Build

```bash
npm run build:ios           # ./scripts/build.sh ipa
npm run build:ios-sim
npm run build:android       # ./scripts/build.sh apk
npm run build:android-unsigned
```

## 6. Clean / Reset

```bash
npm run clean                       # scripts/clean.sh
watchman watch-del-all
rm -rf node_modules && npm install
cd ios && rm -rf Pods Podfile.lock build && cd .. && npm run pod-install
cd android && ./gradlew clean && cd ..
rm -rf $TMPDIR/metro-* $TMPDIR/haste-map-*
```

---

# 7. Bắt API (Network debugging)

App dùng `@mattermost/react-native-network-client` (native networking), **không phải** `fetch`
của JS core — nên một số cách bắt request quen thuộc sẽ không thấy gì. Dưới đây xếp theo
mức độ hiệu quả.

## 7.1 React Native DevTools (nhanh nhất, JS-level)

Cách mở DevTools: xem [8.1](#81-react-native-devtools--cách-mở).

- Tab **Network**: chỉ thấy request đi qua JS `fetch`/`XMLHttpRequest`. App này dùng
  `@mattermost/react-native-network-client` (native) nên **phần lớn API call sẽ không
  hiện ở đây** — muốn bắt đủ, dùng proxy ở 7.2.
- Tab **Sources**: đặt breakpoint trong `app/actions/remote/*`, `app/client/rest/base.ts`
  (`doFetch`) hoặc `app/managers/network_manager.ts` để xem URL, headers, body trước khi gửi.

Cách chắc ăn để thấy **mọi** call ở JS level là log tại tầng client: thêm `logDebug`
trong `app/client/rest/base.ts` (`doFetch`) hoặc `client/rest.ts` của từng product.

## 7.2 Proxy HTTPS — Charles / Proxyman / mitmproxy (khuyến nghị)

Cách này bắt được **native traffic**, kể cả WebSocket.

**mitmproxy (miễn phí)**

```bash
brew install mitmproxy
mitmweb --listen-port 8080          # UI tại http://127.0.0.1:8080
ipconfig getifaddr en0              # lấy IP máy Mac, ví dụ 192.168.1.10
```

**iOS Simulator** — dùng chung proxy hệ thống của macOS:

```bash
# System Settings > Network > Wi-Fi > Details > Proxies > Web Proxy (HTTP/HTTPS) = 127.0.0.1:8080
# Cài CA cert:
open ~/.mitmproxy/mitmproxy-ca-cert.pem     # kéo vào simulator, hoặc:
xcrun simctl keychain booted add-root-cert ~/.mitmproxy/mitmproxy-ca-cert.pem
# Sau đó: Settings > General > About > Certificate Trust Settings > bật trust
```

**Android Emulator**

```bash
emulator -avd <name> -http-proxy http://10.0.2.2:8080
# hoặc: Settings > Wi-Fi > long-press AndroidWifi > Modify > Proxy = Manual, 10.0.2.2:8080
adb push ~/.mitmproxy/mitmproxy-ca-cert.pem /sdcard/
# Settings > Security > Encryption & credentials > Install a certificate > CA certificate
```

**Thiết bị thật**: đặt proxy thủ công trong Wi-Fi settings trỏ tới `<IP-máy-Mac>:8080`,
rồi mở `http://mitm.it` trên máy để tải & trust cert.

**Lọc traffic Mattermost**

```bash
mitmweb --listen-port 8080 --set view_filter='~u /api/v4/'
mitmdump -p 8080 -w /tmp/mm.flow '~u /api/v4/'      # ghi ra file
mitmdump -nr /tmp/mm.flow                            # đọc lại
```

> Android API 24+ chỉ tin user CA khi app khai báo `network_security_config`.
> Repo này đã khai báo sẵn `<certificates src="user" />` trong
> `android/app/src/main/res/xml/network_security_config.xml`, nên chỉ cần cài & trust
> cert là bắt được HTTPS.

## 7.3 Flipper / Proxyman Atlas

Proxyman có Atlas SDK cho RN; Charles Proxy dùng y hệt mitmproxy ở trên
(Charles > Proxy > macOS Proxy cho iOS sim, Help > SSL Proxying > Install cert).

## 7.4 Xem WebSocket

WebSocket (`/api/v4/websocket`) không hiện trong DevTools Network vì chạy native.

```bash
# Log ngay tại client:
# app/client/websocket/index.ts  -> thêm logDebug trong onMessage
```
Hoặc dùng mitmproxy (hỗ trợ WS frames) với filter `~websocket`.

## 7.5 Đổi server để test

Server URL nhập trong màn hình đăng nhập (`app/screens/server/`); giá trị mặc định ở
`assets/base/config.json` (`DefaultServerUrl`). Server tối thiểu: **11.7.0+**.

## 7.6 Lưu ý bảo mật

- Không commit `.env`, `credentials.json`, `google-services.json` chứa key thật.
- Log bị ghi ra file và gửi Sentry — **không log PII** (username, email, nội dung tin nhắn,
  token). Dùng ID thay cho tên hiển thị, và `getFullErrorMessage(error)` thay cho raw error.
- Tắt proxy + gỡ CA cert sau khi debug xong.

---

# 8. Xem log của app

RN 0.83 **có** devtool tương đương Flutter DevTools: **React Native DevTools**
(dựa trên Chrome DevTools, thay cho Flipper/Remote JS Debugger đã bị bỏ).

## 8.1 React Native DevTools — cách mở

RN 0.83 có devtool tương đương Flutter DevTools: **React Native DevTools**, dựa trên
Chrome DevTools protocol (thay cho Flipper và Remote JS Debugger đã bị gỡ bỏ).
Không cần cài gì thêm — nó đi kèm React Native, chỉ cần Metro đang chạy.

**3 cách mở:**

```bash
# 1. Trong terminal đang chạy `npm start`, nhấn phím:
j

# 2. Từ dev menu trên thiết bị -> "Open DevTools"
adb shell input keyevent 82        # Android: mở dev menu
#                                    iOS sim: Cmd+D

# 3. Nhấn `d` trong terminal Metro để bật dev menu từ xa, rồi chọn Open DevTools
```

DevTools mở trong cửa sổ trình duyệt riêng.
Nếu nhấn `j` không có gì xảy ra → xem cách kiểm tra ở [3.6](#36-metro)
(`curl -s http://127.0.0.1:8081/json/list` phải trả về 1 target, không phải `[]`).

**Các tab dùng được:**

| Tab | Dùng để |
|---|---|
| **Console** | Toàn bộ `console.log/debug/warn/error`, tức mọi `logInfo/logDebug/logWarning/logError` |
| **Sources** | Breakpoint, step, xem scope/variables — có source map nên debug thẳng file `.ts/.tsx` |
| **Network** | Chỉ request qua JS `fetch`/XHR — app này dùng native client, xem mục 7 |
| **Memory** | Heap snapshot, tìm memory leak |
| **Components** | React DevTools: cây component, props, state |
| **Profiler** | Đo re-render |

> Yêu cầu Hermes (repo này đã dùng Hermes) + Chrome hoặc Edge.
> DevTools **không** thấy log của native code — xem 8.2.

## 8.2 Log ở terminal

### Metro
Console output in thẳng ra cửa sổ chạy `npm start`.

### Android — `adb logcat`

```bash
export PATH=$PATH:~/Library/Android/sdk/platform-tools

adb logcat *:S ReactNativeJS:V                                    # chỉ log JS, realtime
adb logcat --pid=$(adb shell pidof -s com.thaiduongco.chat)       # toàn bộ log của app
adb logcat -d -t 200 --pid=$(adb shell pidof -s com.thaiduongco.chat)   # dump 200 dòng rồi thoát
adb -s emulator-5554 logcat *:S ReactNativeJS:V                   # chỉ định thiết bị
adb logcat -c                                                      # xoá buffer trước khi tái hiện bug
adb logcat *:S ReactNativeJS:V ReactNative:V ReactNativeNotifs:V   # thêm native + push
```

### iOS

```bash
npx react-native log-ios
xcrun simctl spawn booted log stream --level debug \
  --predicate 'processImagePath CONTAINS "Mattermost"'
```

Code native (Obj-C++ / Kotlin trong `libraries/@mattermost/*`, FCM, notifications) **chỉ**
thấy qua `adb logcat` / `log-ios` hoặc console Xcode / Android Studio.
## 8.3 Hàm log trong code

Không dùng `console.*` trực tiếp. Dùng `@utils/log`:

```ts
import {logDebug, logInfo, logWarning, logError} from '@utils/log';
import {getFullErrorMessage} from '@utils/errors';

logDebug('fetchChannels', channelId);
logError('error on fetchChannels', getFullErrorMessage(error));
```

Mỗi hàm làm 2 việc: in ra console **và** đẩy breadcrumb lên Sentry
(nếu `SentryEnabled` trong `assets/base/config.json`).

## 8.4 Log file trong app (Report a Problem)

Có sẵn màn hình xem/ export file log:

**Settings → Report a Problem → App Logs** (`app/screens/report_a_problem/app_logs.tsx`)
— liệt kê file log, xem nội dung, nén zip và share/save.

⚠️ **Ở bản debug màn hình này sẽ trống.** `index.tsx` cấu hình:

```ts
TurboLogger.configure({
    dailyRolling: false,
    logToFile: !__DEV__,        // <- dev build KHÔNG ghi ra file
    maximumFileSize: 1024 * 1024,
    maximumNumberOfFiles: 2,
});
```

Muốn test ghi file log ở dev, sửa tạm thành `logToFile: true` rồi reload
(nhớ revert trước khi commit).

Lấy file log ra từ máy:

```bash
# Android
adb shell run-as com.thaiduongco.chat ls files/logs
adb exec-out run-as com.thaiduongco.chat cat files/logs/<file>.log > /tmp/app.log

# iOS Simulator
find ~/Library/Developer/CoreSimulator/Devices -name "*.log" -path "*Mattermost*"
xcrun simctl get_app_container booted com.thaiduongco.chat data
```

## 8.5 Sentry

Breadcrumbs + crash gửi lên Sentry khi `SentryEnabled: true` trong
`assets/base/config.json`. Dev build thường tắt — bật lên nếu cần kiểm tra luồng
báo lỗi thật.

⚠️ Log bị export ra file và gửi Sentry → **không log PII** (username, email, display name,
nội dung tin nhắn, token). Chỉ log ID, type, count, boolean.

## 8.6 Database (WatermelonDB)

Không có devtool riêng; xem trực tiếp file SQLite:

```bash
# Android
adb exec-out run-as com.thaiduongco.chat cat databases/<server>.db > /tmp/mm.db
sqlite3 /tmp/mm.db ".tables"

# iOS Simulator
sqlite3 "$(xcrun simctl get_app_container booted com.thaiduongco.chat data)/Documents/<server>.db" ".tables"
```

---

# 9. Push notification (Android)

## 9.1 Luồng hoạt động

```
App (Firebase project chat-701d9)
  └─ FCM cấp token  ─────────────────────────────┐
                                                  ▼
  └─ gửi lên Mattermost server dưới dạng  "android_rn-v2:<fcm-token>"
                                                  ▼
Mattermost server (chat.thaiduongco.com)  ──►  Push Notification Service (push proxy)
                                                  ▼
                                          FCM (phải là CÙNG Firebase project)
                                                  ▼
                                          Thiết bị  ──► CustomPushNotification.kt
```

**Điểm mấu chốt:** `google-services.json` chỉ giúp *app* lấy token. Bên **gửi** là push
proxy — nó phải có **service account JSON của đúng project `chat-701d9`**. Nếu proxy còn
dùng credential của project cũ (`dev-tdc`) thì FCM trả `SenderId mismatch` và noti không
bao giờ tới.

## 9.2 Cấu hình phía app (đã xong)

| Mục | Giá trị |
|---|---|
| File | `android/app/google-services.json` |
| Firebase project | `chat-701d9` |
| Sender ID | `857576174259` |
| App ID | `1:857576174259:android:6b52642ec3bceb1ceab6c6` |
| Package | `com.thaiduongco.chat` |

`google-services.json` là **build-time** — sửa xong phải build lại native, hot reload không
ăn. Sau khi build, kiểm tra giá trị đã được nhúng đúng:

```bash
cat android/app/build/generated/res/processDebugGoogleServices/values/values.xml
cat android/app/build/gmpAppId/debug.txt
```

Firebase tự huỷ token cũ khi `google_app_id` đổi — **không cần gỡ app**. Xác nhận bằng
file installation trong app data (mỗi project một file):

```bash
adb shell run-as com.thaiduongco.chat ls files/ | grep PersistedInstallation
```

## 9.3 Foreground / background / bị kill

Đã được xử lý sẵn, không cần code thêm:

| Trạng thái | Ai xử lý |
|---|---|
| **Foreground** | JS — `onNotificationReceivedForeground` (`app/init/push_notifications.ts`) |
| **Background** | Native `CustomPushNotification.kt` → JS `onNotificationReceivedBackground` |
| **App bị kill / swipe khỏi recents** | Native — `FcmInstanceIdListenerService` (từ `react-native-notifications`) đánh thức process, `MainApplication.getPushNotification()` trả về `CustomPushNotification`, notification được dựng hoàn toàn ở native |

Điều kiện để hoạt động khi app bị kill:
- Mattermost gửi **data message priority = high** (server lo)
- App **không bị force-stop** (Settings → Force stop, hoặc `adb shell am force-stop`).
  Swipe khỏi recents thì vẫn nhận được; force-stop thì Android chặn hoàn toàn FCM.
- Không bị hạn chế pin. Trên máy thật (Xiaomi/Oppo/Samsung...) phải bật **Autostart** và
  đặt battery = **Unrestricted**:

```bash
adb shell dumpsys deviceidle whitelist +com.thaiduongco.chat    # bỏ battery optimization
adb shell cmd appops set com.thaiduongco.chat RUN_IN_BACKGROUND allow
```

- Android 13+: quyền `POST_NOTIFICATIONS` phải được cấp:

```bash
adb shell dumpsys package com.thaiduongco.chat | grep POST_NOTIFICATIONS
adb shell pm grant com.thaiduongco.chat android.permission.POST_NOTIFICATIONS
```

## 9.4 Kiểm tra / debug

**Bước 1 — app đã lấy được token chưa**

```bash
adb logcat -c && adb shell am force-stop com.thaiduongco.chat && \
  adb shell monkey -p com.thaiduongco.chat 1 >/dev/null
adb logcat -d | grep -E "ReactNativeNotifs.*token|Notification token registered"
```

Mong đợi:
```
I ReactNativeNotifs: FCM has a new token=<token>
D ReactNativeJS: 'Notification token registered', 'android_rn-v2:<16 ký tự đầu>...'
```

**Bước 2 — token đã lưu vào app DB chưa**

```bash
adb exec-out run-as com.thaiduongco.chat cat files/databases/app.db > /tmp/app.db
sqlite3 /tmp/app.db "select value from Global where id='deviceToken';"
```

**Bước 3 — server có gửi được tới token đó không** (quan trọng nhất)

```bash
TOKEN=$(sqlite3 /tmp/app.db "select value from Global where id='deviceToken';" | tr -d '"')
curl -s "https://chat.thaiduongco.com/api/v4/system/ping?device_id=$(
  python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$TOKEN")" \
  | python3 -m json.tool
```

| `CanReceiveNotifications` | Nghĩa là |
|---|---|
| `"true"` | Push proxy gửi được → OK |
| `"false"` | Proxy **từ chối token** — sai Firebase credential, hoặc proxy chưa cấu hình Android |
| `"unknown"` | Proxy không phản hồi / token sai định dạng / proxy bản cũ |
| *(không có field)* | Server chưa bật `SendPushNotifications` |

**Bước 4 — trạng thái app đang ghi nhận**

```bash
adb exec-out run-as com.thaiduongco.chat cat \
  "files/databases/$(echo -n 'https://chat.thaiduongco.com' | base64).db" > /tmp/server.db
sqlite3 /tmp/server.db "select value from System where id='pushVerificationStatus';"
sqlite3 /tmp/server.db "select id,value from Config where id like '%ush%';"
```

**Bước 5 — xem noti khi tới**

```bash
adb logcat *:S ReactNativeNotifs:V ReactNativeJS:V FirebaseMessaging:V
```

## 9.5 Nếu `CanReceiveNotifications = "false"` — cần sửa ở server

Trên máy chạy **Mattermost Push Notification Service**:

1. Firebase Console → project **chat-701d9** → ⚙️ Project settings → **Service accounts**
   → *Generate new private key* → tải file JSON.
2. Copy file đó lên máy push proxy, rồi trỏ config tới nó
   (`config/mattermost-push-proxy.json`):

```json
{
  "AndroidPushSettings": [
    {
      "Type": "android",
      "AndroidPushType": "android_rn",
      "ServiceFileLocation": "/etc/mattermost-push-proxy/chat-701d9-service-account.json"
    }
  ]
}
```

3. Restart push proxy, rồi chạy lại **Bước 3** — phải ra `"true"`.

> `AndroidPushType` phải khớp prefix mà app gửi (`android_rn`, xem
> `app/constants/device.ts`). iOS không dùng Firebase — nó đi thẳng APNs, cần file `.p8`
> / `.p12` cấu hình riêng trong cùng push proxy.

**Reset cảnh báo "push disabled" trong app** (app nhớ là bạn đã bấm OK nên sẽ không cảnh
báo lại):

```bash
sqlite3 /tmp/app.db "select id from Global where id like 'pushDisabledAck%';"
# sau khi sửa xong server, xoá app data hoặc logout/login lại để app kiểm tra lại
```

---

# 10. Branding: logo, icon, theme

## 10.1 File nguồn

Toàn bộ logo/icon được sinh ra từ **một file duy nhất**:

```
assets/base/images/tdc_logo.png       1824 × 962, RGBA, nền trong suốt
```

Vùng nội dung thực (bỏ viền trong suốt): `(66, 71) → (1757, 889)` = **1691 × 818**, tỉ lệ **2.067:1**.

Màu thương hiệu lấy từ chính file logo:

| Màu | Hex | Dùng ở |
|---|---|---|
| Navy | `#214090` | chữ "ThaiDuong", tagline |
| Cam | `#F25822` | mặt trời, gạch chân |
| Nền icon/splash | `#FFFFFF` | nền vuông của icon và splash |

## 10.2 Sinh lại toàn bộ icon

Khi đổi logo, thay file `assets/base/images/tdc_logo.png` rồi chạy lại script sinh ảnh
(cần Pillow):

```bash
python3 -m venv /tmp/imgvenv && /tmp/imgvenv/bin/pip install Pillow
/tmp/imgvenv/bin/python scripts/gen_icons.py
/tmp/imgvenv/bin/python scripts/gen_release_splash.py
node scripts/generate-assets.js      # copy assets/base -> dist/assets
npm run android                      # icon là resource native -> phải build lại
```

## 10.3 Danh sách file được sinh

**Android — icon launcher**

| File | Kích thước (mdpi→xxxhdpi) | Nội dung |
|---|---|---|
| `mipmap-*/ic_launcher.png` | 48, 72, 96, 144, 192 | nền trắng đặc, logo 88% chiều rộng |
| `mipmap-*/ic_launcher_round.png` | 48 → 192 | nền tròn trắng, logo 62% (vừa trong đường tròn) |
| `mipmap-*/ic_launcher_foreground.png` | 108, 162, 216, 324, 432 | trong suốt, logo **54%** |
| `mipmap-*/ic_launcher_background.png` | 108 → 432 | trắng đặc |

> Adaptive icon (`mipmap-anydpi-v26/ic_launcher.xml`) có canvas 108dp nhưng **safe zone chỉ
> là đường tròn 66dp ở giữa**. Logo tỉ lệ 2.067:1 vừa khít đường tròn đó khi rộng 54% canvas
> — nên icon không bao giờ bị launcher cắt mất chữ, đổi lại logo trông nhỏ.

**Android — notification**

| File | Kích thước | Ghi chú |
|---|---|---|
| `mipmap-*/ic_notification.png` | 22, 33, 44, 66, 88 | **Chỉ là silhouette trắng của hình mặt trời** |

> Android bắt buộc icon status bar phải đơn sắc — hệ thống tô đè toàn bộ pixel thành trắng.
> Nếu nhét cả wordmark vào, kết quả là một khối trắng không đọc được. Vì vậy icon này chỉ
> giữ hình mặt trời. Đây là giới hạn của Android, không sửa được bằng cách đổi ảnh.
> Tham chiếu trong code: `CustomPushNotificationHelper.java:576` → `R.mipmap.ic_notification`.

**Android — splash**

| File | Kích thước | |
|---|---|---|
| `drawable-*/splash.png` | 96, 192, 288, 384, 480 | logo, nền trong suốt |
| `drawable-night-*/splash.png` | như trên | cùng ảnh |
| `drawable-night-*/splash_background.png` | | copy từ bản light |
| `values-night/colors.xml` → `splashscreen_bg` | | `#090A0B` → `#FFFFFF` |

> Splash để nền trắng ở **cả dark mode**. Nếu giữ nền đen, chữ navy `#214090` gần như
> không đọc được. Layout: `drawable/launch_screen.xml`.

**iOS**

| File | Kích thước |
|---|---|
| `Images.xcassets/AppIcon.appiconset/*.png` | 20 → 1024 (15 file), **không có alpha** |
| `Images.xcassets/SplashIcon.imageset/SplashIcon*.png` | 300, 600, 900 (+ `_Dark`) |
| `Images.xcassets/SplashBackgroundColor.colorset` | light + dark = trắng |
| `Images.xcassets/SplashBackground.imageset/*Dark*.png` | copy từ bản light |

> iOS từ chối app icon có kênh alpha → script ghi các file này ở chế độ RGB.

**Release build** — Fastlane ghi đè splash từ `dist/assets/release/splash_screen/`
(xem `fastlane/Fastfile:680-682, 949`), nên bản release lấy từ:

```
assets/base/release/splash_screen/android/...
assets/base/release/splash_screen/ios/...
```

Hai thư mục này cũng đã được cập nhật.

**Trong app (JS)**

| File | Dùng ở |
|---|---|
| `assets/base/images/icon.png` (152) | icon in-app notification — `app/screens/in_app_notification/icon.tsx` |
| `assets/base/images/logo.png` (667) | asset dự phòng, hiện không được import |
| `assets/base/images/tdc_logo.png` | màn hình Server/Login — `app/screens/server/header.tsx` |

> `@assets/*` trỏ tới **`dist/assets/`**, không phải `assets/base/`
> (`tsconfig.json:44`, `babel.config.js:20`). Sửa file trong `assets/base/` xong phải chạy
> `node scripts/generate-assets.js` để đồng bộ sang `dist/`.

## 10.4 File theme — màu sắc, font chữ

| Thành phần | File | Nội dung |
|---|---|---|
| **Bảng màu** | `app/constants/preferences.ts` → `PREFERENCES.THEMES` | 5 theme sẵn có: `denim` (mặc định), `sapphire`, `quartz`, `indigo`, `onyx`. Mỗi theme ~24 token: `sidebarBg`, `centerChannelBg`, `centerChannelColor`, `buttonBg`, `linkColor`, `mentionBg`, `errorTextColor`, `onlineIndicator`… |
| **Kiểu `Theme`** | `types/api/preferences.d.ts:12` | định nghĩa đầy đủ các token màu |
| **Hàm tiện ích theme** | `app/utils/theme/index.ts` | `makeStyleSheetFromTheme()`, `changeOpacity()`, `blendColors()`, `setThemeDefaults()` |
| **Hook đọc theme** | `app/context/theme/index.tsx` | `useTheme()`; fallback là `Preferences.THEMES.denim` |
| **Font chữ** | `app/utils/typography.ts` | `typography(type, size, style)` — `Heading`/`Body` × 25…1200 × `Light`/`Regular`/`SemiBold`. Font family: **OpenSans** (body) và **Metropolis** (heading) |
| **File font** | `assets/fonts/` | `OpenSans-*.ttf`, `Metropolis-*.ttf`, `compass-icons.ttf` |
| **Màu native Android** | `android/app/src/main/res/values/colors.xml`, `values-night/colors.xml` | `splashscreen_bg`, `white`, `transparent` |
| **Theme native Android** | `android/app/src/main/res/values/styles.xml` | `AppTheme` |
| **Màu native iOS** | `ios/Mattermost/Images.xcassets/SplashBackgroundColor.colorset` | nền splash |

**Quy tắc khi viết style** (theo `CLAUDE.md`):

```ts
// ✅ đúng
const getStyleSheet = makeStyleSheetFromTheme((theme: Theme) => ({
    label: {
        color: theme.centerChannelColor,
        ...typography('Body', 200, 'SemiBold'),
    },
}));

// ❌ sai: hardcode màu, hardcode fontSize/fontWeight/fontFamily
```

Đổi màu chủ đạo của app = sửa các token trong `PREFERENCES.THEMES.denim`
(hoặc thêm một theme mới vào object đó). Ví dụ dùng màu TDC:

```ts
denim: {
    type: 'Denim',
    sidebarBg: '#214090',        // navy TDC
    buttonBg: '#214090',
    linkColor: '#214090',
    mentionBg: '#F25822',        // cam TDC
    // … giữ nguyên các token còn lại
},
```

---

# 11. Test nhận notification — bảng log

## 11.1 Một câu lệnh bắt hết

```bash
export PATH=$PATH:~/Library/Android/sdk/platform-tools

adb logcat -c
adb logcat -s ReactNativeJS:V CustomPushNotification:V ReactNativeNotifs:V ReactNative:V \
  "Mattermost Notifications Signature verification:V"
```

Lọc gọn hơn, chỉ lấy dòng liên quan notification:

```bash
adb logcat | grep --line-buffered -E \
  "PushNotifications\.|CustomPushNotification|ReactNativeNotifs|canReceiveNotifications|Notification token"
```

## 11.2 Log ở tầng JS (tag `ReactNativeJS`)

Tất cả dùng tiền tố `PushNotifications.<hàm>` nên grep được theo nhóm.

| Log | Ở đâu | Cho biết |
|---|---|---|
| `PushNotifications: Initializing` | `push_notifications.ts:59` | singleton gắn listener |
| `PushNotifications.registerIfNeeded: isRegistered <bool>` | `:82` | thiết bị đã đăng ký remote notification chưa |
| `PushNotifications.registerIfNeeded: permission status <status>` | `:85` | kết quả xin quyền `POST_NOTIFICATIONS` |
| `Notification token registered android_rn-v2:<16 ký tự>...` | `:342` | **đã lấy được FCM token** (chỉ log 16 ký tự đầu, không lộ token) |
| `Notification registration denied` / `failed` | `:351`, `:355` | người dùng từ chối quyền / FCM lỗi |
| `canReceiveNotifications <url> verification= <true\|false\|unknown> hasAck=` | `push_proxy.ts:23` | **server có gửi được tới token này không** |
| `PushNotifications.processNotification: type= ackId=` | `:240` | notification vào tới JS, loại `message`/`clear`/`session` |
| `PushNotifications.handleMessageNotification <url> foreground= userInteraction= channelId= postId= rootId= ackId=` | `:204` | chọn nhánh nào: in-app / mở khi bấm / xử lý nền |
| `PushNotifications.handleInAppNotification <url> visibleScreen= isThread= sameChannel= crt= willShow=` | `:188` | **vì sao banner in-app hiện hay không hiện** |
| `PushNotifications.handleClearNotification <url> channelId= rootId=` | `:120` | notification kiểu clear (đọc ở máy khác) |
| `PushNotifications.getServerUrlFromNotification: no server matched serverId=` | `:111` | không map được `server_id` → server nào (nguyên nhân notification bị bỏ im lặng) |
| `PushNotifications.onNotificationReceivedForeground: appState= type= ackId=` | `:306` | app đang mở và nhận được |
| `PushNotifications.onNotificationReceivedBackground: type= ackId=` | `:274` | app ở nền và nhận được |
| `PushNotifications.onNotificationOpened: user tapped a notification` | `:264` | người dùng bấm vào notification |
| `not handling {background,foreground} notification because it was not verified, ackId=` | `:277`, `:309` | chữ ký notification sai → bị chặn |

## 11.3 Log ở tầng native Android

Đây là tầng **duy nhất chạy khi app đã bị kill** — nếu không thấy log nào ở đây thì push
chưa tới được thiết bị.

| Tag | Log | Cho biết |
|---|---|---|
| `ReactNativeNotifs` | `FCM has a new token=…` | Firebase cấp token mới |
| `CustomPushNotification` | `onReceived type= channelId= postId= ackId= notificationId= idLoaded= serverResolved= hasSignature=` | **FCM đã giao push xuống máy** (`CustomPushNotification.kt:56`) |
| `CustomPushNotification` | `finishProcessing type= channelId= notificationId= reactInit= appVisible= mainActivity= activity=` | quyết định có dựng notification hay không (`:113`) |
| `Mattermost Notifications Signature verification` | `Notification skipped because we could not verify it.` | chữ ký sai → bỏ notification |
| `ReactNative` | `Start fetching notification data in server=… for channel=… and ack=…` | tải nội dung post (`PushNotificationDataHelper.kt:58`) |
| `ReactNative` | `Done processing push notification=…` | ghi xong vào DB (`:119`) |
| `ReactNative` | `Error processing push notification error=…` | lỗi khi xử lý (`:124`) |

## 11.4 Quy trình test 3 trạng thái

**Chuẩn bị**

```bash
adb logcat -c
# Kiem tra server co gui duoc khong (phai ra "true")
adb exec-out run-as com.thaiduongco.chat cat files/databases/app.db > /tmp/app.db
TOKEN=$(sqlite3 /tmp/app.db "select value from Global where id='deviceToken';" | tr -d '"')
curl -s "https://chat.thaiduongco.com/api/v4/system/ping?device_id=$(
  python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$TOKEN")" \
  | python3 -m json.tool | grep CanReceiveNotifications
```

**1. Foreground** — mở app, nhờ người khác gửi tin ở channel khác

```
CustomPushNotification: onReceived type=message …
ReactNativeJS: PushNotifications.onNotificationReceivedForeground: appState= active …
ReactNativeJS: PushNotifications.processNotification: type= message …
ReactNativeJS: PushNotifications.handleMessageNotification … foreground= true …
ReactNativeJS: PushNotifications.handleInAppNotification … willShow= true
```

**2. Background** — bấm Home (app còn trong recents)

```bash
adb shell input keyevent KEYCODE_HOME
```
```
CustomPushNotification: onReceived …
CustomPushNotification: finishProcessing … appVisible=false mainActivity=false
ReactNative: Start fetching notification data in server=… for channel=…
ReactNative: Done processing push notification=…
```

**3. App bị kill** — swipe khỏi recents (**không** dùng Force stop)

```bash
adb shell input keyevent KEYCODE_APP_SWITCH   # roi swipe app khoi recents bang tay
# hoac dong app "sach" nhung van nhan duoc push:
adb shell am kill com.thaiduongco.chat        # kill process, KHONG phai force-stop
```
```
CustomPushNotification: onReceived …          <- chi con log native
ReactNative: Start fetching notification data …
```

> `adb shell am kill` giết process nhưng Android vẫn giao FCM.
> `adb shell am force-stop` thì Android **chặn hẳn** FCM cho tới khi user mở lại app —
> dùng lệnh này là test sai.

**Không thấy log nào?** Đi từ dưới lên:

1. Không có `CustomPushNotification: onReceived` → push chưa xuống máy. Kiểm tra
   `CanReceiveNotifications` (mục 9.4 bước 3) và push proxy.
2. Có `onReceived` nhưng không có notification hiện ra → xem `finishProcessing`
   (`appVisible`/`mainActivity`) và log signature verification.
3. Có notification native nhưng JS không phản ứng → xem `PushNotifications.processNotification`
   và `getServerUrlFromNotification: no server matched`.

> Log debug build **không** ghi ra file (`index.tsx` đặt `logToFile: !__DEV__`), nên phải
> xem qua `adb logcat`. Xem mục 8.4 nếu cần bật ghi file.

---

# 12. Bản dịch tiếng Việt (i18n)

## 12.1 File & quy tắc

| File | Vai trò |
|---|---|
| `assets/base/i18n/en.json` | **Nguồn sự thật.** Không sửa tay — khai báo `defineMessages()` trong code rồi chạy `npm run i18n-extract` |
| `assets/base/i18n/vi.json` | Bản dịch của fork TDC. **Được sửa trực tiếp** (fork này không đồng bộ Weblate) |
| các `*.json` ngôn ngữ khác | Để nguyên cho upstream/Weblate |
| `dist/assets/i18n/` | Bản build. `@assets/*` trỏ vào đây → sửa `assets/base/` xong phải chạy `node scripts/generate-assets.js` |

Chuỗi thiếu trong `vi.json` sẽ fallback về tiếng Anh và in cảnh báo
`[@formatjs/intl Error MISSING_TRANSLATION]` ra console — đó chính là hiện tượng
"lẫn lộn Anh/Việt" trong UI.

## 12.2 Kiểm tra

```bash
python3 scripts/i18n_check.py
```

Script so `vi.json` với `en.json` và báo lỗi khi:
- thiếu key (sẽ fallback tiếng Anh) hoặc có key lạ không tồn tại trong `en.json`
- `vi.json` chưa sort theo key
- lệch **tên tham số ICU** (`{count}`, `{applicationName}`…) — placeholder có trong bản dịch
  mà không có trong bản gốc sẽ hiện ra nguyên văn `{applicationName}` trên UI
- lệch cấu trúc `plural` / `select` (thiếu nhánh `one`/`other`/`=1`, mất ký tự `#`)
- lệch số ngoặc, số dòng, khoảng trắng đầu/cuối

`scripts/i18n_icu.py` là parser ICU tối thiểu mà script trên dùng. Nó phân biệt được
**tên tham số** và **thân nhánh plural**, nên không báo sai ở những chuỗi kiểu:

```
{count, plural, one {this connection} other {these connections}}
```
→ `{count}` là tham số (giữ nguyên), còn `{this connection}` là nội dung nhánh (**phải dịch**).

## 12.3 Tìm chuỗi chưa dịch khi đang chạy app

```bash
adb logcat -c
adb shell am force-stop com.thaiduongco.chat
adb shell monkey -p com.thaiduongco.chat 1
adb logcat -d | grep -o 'Missing message: "[^"]*"' | sort -u
```

> Sửa `vi.json` xong phải **force-stop rồi mở lại app** — file i18n được `require` vào bundle
> nên chỉ reload thường (`r` ở Metro) có thể vẫn dùng bản cũ.

## 12.4 Thuật ngữ thống nhất

| Tiếng Anh | Tiếng Việt |
|---|---|
| channel | kênh |
| team | nhóm |
| thread | chủ đề |
| post / message | tin nhắn (nghĩa "bài đăng" thì dùng *bài đăng*) |
| server | máy chủ |
| mention | đề cập |
| draft | bản nháp |
| scheduled post | tin nhắn hẹn giờ |
| checklist | danh sách tác vụ |
| run (Playbooks) | lượt chạy |
| playbook | *giữ nguyên* |
| agent / AI agent | trợ lý AI (tên sản phẩm **Agents** giữ nguyên) |
| bookmark | đánh dấu |
| attachment | tệp đính kèm |
| participant | người tham gia |
| workspace | không gian làm việc |
| burn-on-read | tự xoá sau khi đọc |
| Mattermost, SAML, LDAP, GitLab, Entra ID, Bluetooth | *giữ nguyên* |

---

# 13. Chẩn đoán "không nhận được thông báo"

## 13.1 Chạy script chẩn đoán

```bash
./scripts/push_doctor.sh
```

Script đi lần lượt 7 bước dọc đường đi của push và chỉ ra bước nào vỡ:

| Bước | Kiểm tra |
|---|---|
| 1 | thiết bị adb + app có đang chạy |
| 2 | `POST_NOTIFICATIONS` + `importance` (người dùng có tắt thông báo không) |
| 3 | sender ID trong `google-services.json` **so với** token thực tế trên máy |
| 4 | `deviceToken` trong `app.db` + tiền tố `android_rn-v2` |
| 5 | `CanReceiveNotifications` từ server |
| 6 | gọi ping rồi soi logcat — **test push của server có thật sự tới máy không** |
| 7 | `pushVerificationStatus` mà app đã cache |

## 13.2 Kết quả đo được trên server `chat.thaiduongco.com`

Phía app **đã đúng hết**:

| | |
|---|---|
| FCM token | cấp bởi đúng project `chat-701d9` (sender `857576174259`), lưu trong GMS |
| `deviceToken` trong app DB | `android_rn-v2:eYbVu8-FQKak-51m…` — đúng tiền tố |
| Đăng ký lên session server | `PUT /api/v4/users/sessions/device` qua `setExtraSessionProps`, không có log lỗi |
| `POST_NOTIFICATIONS` | granted, channel importance = DEFAULT |
| Xử lý foreground/background/killed | có sẵn ở native `CustomPushNotification.kt` |

Phía server **hỏng**:

```
GET /api/v4/system/ping?device_id=android_rn-v2:<token>
→ "CanReceiveNotifications": "false"
```

Test push của server **không để lại dòng log nào** trên thiết bị → không có gì tới máy.

## 13.3 Bằng chứng lỗi nằm ở push proxy, không ở app

Thăm dò `/api/v4/system/ping` bằng nhiều `device_id` khác nhau:

| `device_id` | Kết quả |
|---|---|
| token thật (project `chat-701d9`) | `false` |
| token cũ (project `dev-tdc`) | `false` |
| **token bịa hoàn toàn**, đúng định dạng FCM | `false` |
| token iOS `apple_rn-v2:<64 hex>` | `false` |
| token sai định dạng / không tiền tố | `unknown` |

**Nếu push proxy gửi được thì token thật phải ra `true`, còn token bịa mới ra `false`.**
Ở đây mọi token đều `false` như nhau, kể cả iOS → proxy từ chối **mọi** thiết bị, không phân
biệt token nào. Tức là nó chưa bao giờ gọi tới FCM/APNs.

Đo độ trễ: gọi ping *có* `device_id` mất ~0.40s, *không có* mất ~0.21s → server vẫn gọi ra
proxy và nhận phản hồi trong ~180ms. **Proxy sống, chỉ là không gửi được.**

Kết luận: Mattermost Push Notification Service đang chạy nhưng **không có credential
Android/iOS nào được nạp** (hoặc `AndroidPushType` không khớp `android_rn`).

## 13.4 Cần làm trên máy chạy push proxy

1. Firebase Console → project **chat-701d9** → ⚙️ Project settings → **Service accounts**
   → *Generate new private key* → tải file JSON.
2. Copy lên máy push proxy và sửa `config/mattermost-push-proxy.json`:

```json
{
  "AndroidPushSettings": [
    {
      "Type": "android",
      "AndroidPushType": "android_rn",
      "ServiceFileLocation": "/etc/mattermost-push-proxy/chat-701d9-service-account.json"
    }
  ]
}
```

3. Restart proxy, kiểm tra log của chính proxy khi khởi động — nó phải in ra là đã nạp
   được `android_rn`. Rồi chạy lại `./scripts/push_doctor.sh`, bước 5 phải ra `true`.

> `AndroidPushType` phải khớp tiền tố app gửi (`android_rn`, xem `app/constants/device.ts:20`).
> iOS cần `ApplePushSettings` với file `.p8`/`.p12` riêng — không dùng Firebase.

## 13.5 Tách biệt lỗi Firebase vs lỗi proxy

Khi đã có service account JSON, gửi push **trực tiếp qua FCM**, bỏ qua Mattermost:

```bash
pip install google-auth requests
adb exec-out run-as com.thaiduongco.chat cat files/databases/app.db > /tmp/app.db
TOKEN=$(sqlite3 /tmp/app.db "select value from Global where id='deviceToken';" | tr -d '"' | cut -d: -f2-)
python3 scripts/fcm_test.py ~/Downloads/chat-701d9-xxxxx.json "$TOKEN"
```

| Kết quả | Nghĩa là |
|---|---|
| HTTP 200 **và** logcat có `CustomPushNotification: onReceived` | Firebase + thiết bị OK → lỗi 100% ở push proxy |
| HTTP 200 nhưng logcat trống | Lỗi ở thiết bị: bị force-stop, bị hạn chế pin, hoặc thiếu Play Services |
| `UNREGISTERED` / `SenderId mismatch` | Service account và `google-services.json` khác project |

## 13.6 Sau khi sửa xong proxy — phải reset trạng thái app

App đã cache `pushVerificationStatus = "not_available"` trong DB của server, và
`verifyPushProxy()` (`app/actions/remote/entry/common.ts:327`) **early-return nếu giá trị này
đã được đặt** — nên app sẽ không bao giờ kiểm tra lại, icon cảnh báo ⚠ vẫn nằm đó.

```bash
# kiem tra
adb exec-out run-as com.thaiduongco.chat cat \
  "files/databases/$(printf '%s' 'https://chat.thaiduongco.com' | base64).db" > /tmp/server.db
sqlite3 /tmp/server.db "select value from System where id='pushVerificationStatus';"
```

Cách reset: **logout rồi login lại**, hoặc `adb shell pm clear com.thaiduongco.chat`
(xoá sạch dữ liệu app).

Ngoài ra `pushDisabledAck<base64-url>` trong `app.db` đang là `true` (đã bấm OK cho cảnh báo
"push bị tắt"), nên cảnh báo đó cũng không hiện lại. Lưu ý: **hai cờ này chỉ ảnh hưởng cảnh
báo trên UI, không chặn việc nhận push** — push vẫn tới bình thường ngay khi proxy được sửa.

---

# 14. `tdc.sh` — bảng điều khiển terminal

Một file duy nhất ở gốc dự án, gom toàn bộ việc hằng ngày vào một menu.
**Không cần cài gì thêm** — bash thuần, không dùng `dialog`/`whiptail`/npm package, chạy được
trên bash 3.2 mặc định của macOS.

```bash
./tdc.sh
```

```
  TDC Chat  v2.44.0 (815)  release-2.44
  Metro on  emulator-5554  reverse ok
  ────────────────────────────────────────────────────────────

  Chon viec can lam

   1  Chay & Debug
   2  Build  (APK / AAB / IPA)
   3  Kiem tra  (lint / tsc / test)
   4  Thiet bi & Log
   5  Cong cu du an
      ······························
   6  Thoat

  mui len/xuong hoac k/j · Enter chon · phim tat ben trai · q quay lai
```

Thanh trạng thái phía trên cập nhật mỗi lần vẽ lại: Metro có chạy không, thiết bị nào đang
kết nối, `adb reverse` đã set chưa, phiên bản + build number + nhánh git.

Điều hướng: **↑ ↓** hoặc **k j**, **Enter** chọn, **phím tắt bên trái** (1–9 rồi a, b, c…),
**q** hoặc **Esc** quay lại / thoát.

## 14.1 Các mục

| Menu | Có gì |
|---|---|
| **Chạy & Debug** | Metro (cửa sổ Terminal mới / reset cache / kill), **khởi động máy ảo**, Android build+install, build+install+**log gỡ lỗi**, mở app không build, xem log gỡ lỗi, `adb reverse`, dev menu, **bắt HTTPS qua Proxyman/Charles**, iOS (mở simulator / chạy mặc định / chọn từ danh sách / thiết bị thật / log gỡ lỗi) |
| **Build** | APK debug, APK release, **AAB release** (`bundleRelease`, để lên Play Store), các lane Fastlane (APK/AAB/IPA, signed và unsigned), iOS cho simulator, và "Xem các file đã build" kèm dung lượng |
| **Kiểm tra** | `check`, `check-test`, `lint`, `fix`, `tsc`, `test`, test theo pattern (nhập từ bàn phím), `test:watch`, `test:coverage`, i18n check |
| **Thiết bị & Log** | liệt kê thiết bị/AVD, **khởi động máy ảo**, **log gỡ lỗi TDCDBG** (gập/mở từng request), log JS, log toàn bộ app theo pid, log push notification, dump 200 dòng, xoá buffer, log iOS, chụp ảnh màn hình, force stop, gỡ app (có bước xác nhận) |
| **Công cụ dự án** | thông tin môi trường, `push_doctor.sh`, sinh lại icon/splash, đồng bộ assets, `npm install`, `pod install`, `clean`, reset sâu (có xác nhận), `i18n-extract` |

Khi có nhiều thiết bị, các mục Android sẽ hỏi chọn thiết bị trước; chỉ có một thì tự dùng
luôn. Không có thiết bị nào thì script hỏi `Khởi động máy ảo ngay? [Y/n]` rồi bật giúp.
Mục Android build/mở app tự chạy `adb reverse` giúp.

Log gỡ lỗi `TDCDBG` (màn hình đang mở, API kèm header/body, sự kiện WebSocket) và cách
bắt HTTPS bằng Proxyman/Charles: xem mục 7 của [`README.md`](README.md).

## 14.2 Gọi trực tiếp, không qua menu

Tiện cho CI hoặc khi đã biết mình cần gì:

```bash
./tdc.sh apk            # APK debug   (gradlew assembleDebug)
./tdc.sh apk-release    # APK release (gradlew assembleRelease)
./tdc.sh aab            # AAB release (gradlew bundleRelease)
./tdc.sh ipa            # IPA qua Fastlane
./tdc.sh ios-sim        # build iOS cho simulator
./tdc.sh emulator       # bật máy ảo Android rồi chờ khởi động xong
./tdc.sh avds           # liệt kê máy ảo đã tạo
./tdc.sh simulator      # mở iOS simulator
./tdc.sh android        # build + cài đặt + mở trên Android
./tdc.sh android-log    # build + cài + mở rồi mở bộ xem log gỡ lỗi
./tdc.sh ios            # chạy trên iOS simulator
./tdc.sh metro          # Metro (reset cache)
./tdc.sh trace          # bộ xem log gỡ lỗi: màn hình + API + WebSocket
./tdc.sh trace-text     # như trên, xả thẳng ra terminal
./tdc.sh trace-ios      # bộ xem log trên iOS simulator
./tdc.sh proxy          # trỏ máy ảo qua Proxyman/Charles (proxy off để tắt)
./tdc.sh log            # log JS
./tdc.sh log-push       # log push notification
./tdc.sh check          # lint + tsc
./tdc.sh test           # jest
./tdc.sh doctor         # thông tin môi trường
./tdc.sh push-doctor    # chẩn đoán push notification
./tdc.sh help
```

Muốn gọi qua npm thì thêm vào `package.json`:

```json
"scripts": { "tdc": "./tdc.sh" }
```

## 14.3 Ghi chú kỹ thuật

- Script tự thêm `platform-tools` và `emulator` vào `PATH` nếu tìm thấy Android SDK, nên
  không cần `export PATH` trước khi chạy.
- Terminal được đặt sang chế độ **cbreak** (`stty -icanon -echo min 1 time 0`) trong lúc hiện
  menu, và trả về nguyên trạng trước khi chạy bất kỳ lệnh nào — nên `Ctrl+C` vẫn dừng được
  build, và shell của bạn không bị hỏng khi thoát.
- Phím được đọc bằng `dd` thay vì `read -sn1`: `read -sn1` gọi `tcsetattr` mỗi lần đọc, và
  trên macOS việc đó **làm mất các byte còn lại trong bộ đệm**, khiến mũi lên/xuống (3 byte
  `ESC [ A`) không bao giờ đọc đủ.
- **Không chớp khi bấm mũi:** menu không dùng `\033[2J` (xoá cả màn hình) vì nó tạo ra một
  khung trống giữa hai lần vẽ. Thay vào đó `\033[H` + `\033[K` từng dòng, và khi bấm mũi thì
  **chỉ vẽ lại 2 dòng** (dòng cũ và dòng mới) bằng cách đặt con tro tuyệt đối — mỗi lần bấm
  chỉ ghi ~115 byte, không gọi lệnh ngoài nào.
- Thanh trạng thái (`lsof` + `adb` + `git`) chỉ tính lại khi vào menu hoặc sau khi chạy xong
  một lệnh, không tính mỗi lần bấm phím.
- "Metro ở cửa sổ Terminal mới" dùng `osascript` nên chỉ hoạt động trên macOS; các nền tảng
  khác sẽ được nhắc chạy `npm start` thủ công.

---

# 15. Lỗi build hay gặp

## 15.1 `[CXX1409] expected buildFiles file '.../codegen/jni/CMakeLists.txt' to exist`

```
Execution failed for task ':app:configureCMakeRelWithDebInfo[arm64-v8a]'.
> [CXX1409] .../android/app/.cxx/RelWithDebInfo/3t3k3x2v/arm64-v8a/android_gradle_build_mini.json
  unsigned|arm64-v8a : expected buildFiles file
  '.../node_modules/react-native-image-picker/android/build/generated/source/codegen/jni/CMakeLists.txt'
  to exist
```

**Nguyên nhân.** Với New Architecture, mỗi thư viện có `codegenConfig` sẽ sinh ra một
`CMakeLists.txt` trong `node_modules/<lib>/android/build/generated/source/codegen/jni/`.
Gradle ghi **đường dẫn tuyệt đối** của các file đó vào metadata CMake tại
`android/app/.cxx/<buildType>/<hash>/<abi>/android_gradle_build_mini.json`.

`scripts/build.sh` (tức `npm run build:android*` / `build:ios*`) gọi `setup()` → `npm run clean`,
mà `clean.sh` xoá `node_modules` **nhưng trước đây không xoá `android/app/.cxx`**. Sau khi cài
lại node_modules, `.cxx` vẫn giữ đường dẫn cũ trỏ vào thư mục `build/` đã bị xoá. Task
`configureCMake*` kiểm tra từng đường dẫn trong `buildFiles` trước khi cấu hình lại → dừng
với CXX1409. Thư viện nào bị báo là tuỳ thứ tự, không riêng `react-native-image-picker`.

**Đã sửa gốc:** thêm `rm -rf android/app/.cxx` vào `scripts/clean.sh`, nên từ giờ
`npm run clean` và các lane Fastlane không gặp lại lỗi này.

**Nếu đã gặp rồi** (`.cxx` đang bị hỏng sẵn):

```bash
./tdc.sh fix-cxx          # hoac: Cong cu du an > Sua loi build CXX1409
```

hoặc thủ công:

```bash
rm -rf android/app/.cxx
```

Lần build sau CMake cấu hình lại từ đầu nên chậm hơn vài phút, sau đó trở lại bình thường.

> Kiểm tra xem `.cxx` có đang trỏ vào đường dẫn hư không:
> ```bash
> python3 -c "
> import json, glob, os
> for f in glob.glob('android/app/.cxx/*/*/*/android_gradle_build_mini.json'):
>     for p in json.load(open(f)).get('buildFiles', []):
>         if not os.path.exists(p):
>             print('THIEU:', p); break
> "
> ```

## 15.2 `[CXX1429]` / `error opening '....o.d': No such file or directory` — chạy hai build song song

Các triệu chứng dưới đây **đều là cùng một nguyên nhân**: file bị xoá ngay giữa lúc đang dùng.

| Triệu chứng | Log |
|---|---|
| CMake try-compile vỡ | `ninja: error: loading 'build.ninja': No such file or directory` |
| ID try-compile lệch nhau | `unknown target 'cmTC_ef57b', did you mean 'cmTC_8f521'?` |
| Chọn sai linker | `ld64.lld: error: unknown argument '--build-id=sha1'` (ld64.lld là linker **macOS**, không phải Android) |
| Thư mục output biến mất | `error opening '..../States.cpp.o.d': No such file or directory` |

**Nguyên nhân: hai build chạy song song trên cùng thư mục dự án.** Gradle dùng
`android/app/.cxx` và `android/app/build` làm vùng làm việc dùng chung; hai tiến trình
`gradlew` — hoặc một build cộng một `npm run clean` — sẽ xoá file của nhau.

Hai điều làm nó tệ hơn:

- `scripts/build.sh` (mọi `npm run build:*`) gọi `npm run clean`, tức **xoá** `node_modules`,
  `android/app/build` và `android/app/.cxx`. Chạy nó song song với build khác thì chắc chắn vỡ.
- `unsigned.initWith(buildTypes.release)` làm hai variant `release` và `unsigned` sinh **cùng
  hash `.cxx`** (tham số CMake giống nhau) → dùng chung một thư mục.

**Không phải** do NDK, toolchain, hay Gradle build cache. Đã loại trừ từng cái:

| Giả thuyết | Kiểm chứng |
|---|---|
| NDK 27.1 bỏ `x86` | `meta/abis.json` có `x86 → i686-none-linux-android`, `deprecated: false`, sysroot đầy đủ |
| Toolchain x86 hỏng | gọi `cmake` bằng tay với đúng tham số đó → `Detecting CXX compile features - done` |
| Build cache (`org.gradle.caching=true`) | xoá `.cxx/x86` rồi configure **có** cache → SUCCESSFUL 5s |
| Task chạy trùng | log chỉ có 1 `configureCMakeRelWithDebInfo[x86]` |
| Cấu hình 4 ABI cùng lúc | xoá sạch `.cxx` rồi configure cả 4 → SUCCESSFUL 8s |

Chạy lại **một mình**: `assembleRelease` thành công trong 4m33s, và bộ theo dõi `.cxx` cho thấy
số `build.ninja` tăng đều 1→8 mà không lần nào biến mất.

### Kiểm tra có build nào khác đang chạy

```bash
pgrep -fl GradleDaemon | grep -oE 'GradleDaemon [0-9.]+'
for p in $(pgrep -f GradleDaemon); do
  echo "pid $p -> $(lsof -p "$p" 2>/dev/null | grep -c mattermost-mobile) file trong project"
done
```

Daemon nào đang giữ file trong project thì đang build. Nhớ cả **Android Studio** — nó tự sync
nền và cũng động vào `.cxx`.

### Theo dõi `.cxx` trong lúc build (khi cần chứng minh)

```bash
D=android/app/.cxx; prev=
while :; do
  [ -d "$D" ] && now="có ($(find "$D" -name build.ninja 2>/dev/null | wc -l | tr -d ' ') build.ninja)" || now="KHÔNG CÓ"
  [ "$now" != "$prev" ] && echo "$(date '+%H:%M:%S')  .cxx: $now"
  prev=$now; sleep 2
done
```

Nếu thấy `.cxx` chuyển sang `KHÔNG CÓ` giữa build → đúng là có tiến trình khác xoá nó.

### Cách xử lý

```bash
pkill -f GradleDaemon        # dung het daemon
./tdc.sh fix-cxx             # xoa metadata CMake
./tdc.sh apk-arm64           # build lai, VA KHONG chay gi khac cung luc
```

---

## 15.3 In đường dẫn file sau khi build

`tdc.sh` tự in ra đường dẫn + dung lượng của file vừa tạo sau **mỗi** lần build thành công
(cả trong menu và khi gọi trực tiếp):

```
  ✓ xong trong 214s

  File vua tao:
      329M  app-release.apk
            /Users/mwang/Projects/TDC/mattermost-mobile/android/app/build/outputs/apk/release/app-release.apk

  Cai len may:  adb install -r "/Users/mwang/.../app-release.apk"
```

Cách hoạt động: trước khi build, script tạo một file mốc thời gian bằng `mktemp`, sau đó
`find ... -newer <mốc>` trong `android/app/build/outputs`, `ios/build` và thư mục gốc dự án
(Fastlane chuyển file đã build ra gốc) — nên chỉ liệt kê file **của lần build này**, không
lẫn file cũ.

Xem lại toàn bộ file đã build bất kỳ lúc nào (kèm thời gian tạo):

```bash
./tdc.sh artifacts        # hoac: Build > Xem cac file da build
```

## 15.4 Build nhanh chỉ cho máy thật

`reactNativeArchitectures` trong `android/gradle.properties` mặc định là cả 4 ABI
(`armeabi-v7a,arm64-v8a,x86,x86_64`). Máy Android thật ngày nay đều là **arm64-v8a**; `x86`/`x86_64`
chỉ dùng cho emulator. Bỏ chúng đi thì build nhanh hơn khoảng 3 lần:

```bash
./tdc.sh apk-arm64
# tuong duong:
cd android && ./gradlew app:assembleRelease -PreactNativeArchitectures=arm64-v8a
```

Trong menu: **Build → APK release chỉ arm64-v8a**.

Chỉ cần đủ 4 ABI khi nộp lên store — và lúc đó nên dùng **AAB** (`./tdc.sh aab`), vì Play Store
tự tách theo thiết bị nên người dùng không phải tải phần ABI không liên quan.
