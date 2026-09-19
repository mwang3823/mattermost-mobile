#!/usr/bin/env bash
# Chan doan tu dau den cuoi duong di cua push notification (Android).
#   ./scripts/push_doctor.sh [serverUrl]
set -uo pipefail

PKG=com.thaiduongco.chat
SERVER=${1:-https://chat.thaiduongco.com}
export PATH=$PATH:$HOME/Library/Android/sdk/platform-tools

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

enc() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }

hdr "1. Thiet bi & app"
if ! adb devices | grep -q "device$"; then bad "khong co thiet bi adb nao"; exit 1; fi
ok "adb: $(adb devices | awk '/device$/{print $1}' | tr '\n' ' ')"
PID=$(adb shell pidof -s "$PKG" 2>/dev/null | tr -d '\r')
[ -n "$PID" ] && ok "app dang chay (pid $PID)" || warn "app khong chay — mo app roi chay lai"

hdr "2. Quyen thong bao (Android 13+)"
if adb shell dumpsys package "$PKG" | grep -q "POST_NOTIFICATIONS: granted=true"; then
  ok "POST_NOTIFICATIONS da duoc cap"
else
  bad "POST_NOTIFICATIONS CHUA cap -> adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS"
fi
IMP=$(adb shell dumpsys notification 2>/dev/null | grep -m1 "AppSettings: $PKG" | sed 's/.*importance=//;s/ .*//' | tr -d '\r')
[ "$IMP" = "NONE" ] && bad "nguoi dung da tat thong bao cua app (importance=NONE)" || ok "importance=$IMP"

hdr "3. Firebase project dang dung"
GMS=$(adb shell run-as "$PKG" cat shared_prefs/com.google.android.gms.appid.xml 2>/dev/null)
SENDERS=$(echo "$GMS" | grep -o '|T|[0-9]*|' | tr -d '|T' | sort -u | tr '\n' ' ')
CFG_SENDER=$(python3 -c "import json;print(json.load(open('android/app/google-services.json'))['project_info']['project_number'])" 2>/dev/null)
echo "  google-services.json  : sender $CFG_SENDER"
echo "  token da cap tren may : sender(s) $SENDERS"
if echo "$SENDERS" | grep -qw "$CFG_SENDER"; then
  ok "may da co token cho dung project trong google-services.json"
else
  bad "may CHUA co token cho sender $CFG_SENDER -> build lai native (google-services.json la build-time)"
fi

hdr "4. Token trong DB cua app"
adb exec-out run-as "$PKG" cat files/databases/app.db > /tmp/pd_app.db 2>/dev/null
TOKEN=$(sqlite3 /tmp/pd_app.db "select value from Global where id='deviceToken';" 2>/dev/null | tr -d '"')
if [ -z "$TOKEN" ]; then
  bad "chua co deviceToken — app chua dang ky duoc voi FCM"; exit 1
fi
ok "deviceToken = ${TOKEN:0:32}... (${#TOKEN} ky tu)"
case "$TOKEN" in android_rn-v2:*) ok "prefix dung: android_rn-v2" ;; *) bad "prefix la khac: ${TOKEN%%:*}" ;; esac

hdr "5. Server co gui duoc toi token nay khong"
RESP=$(curl -s -m 30 "$SERVER/api/v4/system/ping?device_id=$(enc "$TOKEN")")
CRN=$(echo "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('CanReceiveNotifications'))" 2>/dev/null)
VER=$(curl -s -m 15 "$SERVER/api/v4/config/client?format=old" | python3 -c "import sys,json;print(json.load(sys.stdin).get('Version'))" 2>/dev/null)
echo "  server $SERVER (Mattermost $VER)"
case "$CRN" in
  true)      ok "CanReceiveNotifications=true — push proxy gui duoc" ;;
  false)     bad "CanReceiveNotifications=false — push proxy TU CHOI gui. Loi o cau hinh push proxy, khong phai o app." ;;
  unknown)   warn "CanReceiveNotifications=unknown — proxy khong phan hoi / phien ban proxy cu" ;;
  None|'')   bad "server khong tra ve field nay — SendPushNotifications dang tat" ;;
  *)         warn "gia tri la: $CRN" ;;
esac

hdr "6. Test push cua server co den thiet bi khong"
adb logcat -c
curl -s -m 30 "$SERVER/api/v4/system/ping?device_id=$(enc "$TOKEN")" >/dev/null
sleep 6
HITS=$(adb logcat -d 2>/dev/null | grep -cE "CustomPushNotification: onReceived|ReactNativeNotifs.*[Mm]essage")
if [ "$HITS" -gt 0 ]; then
  ok "co $HITS dong log — push DA den thiet bi"
  adb logcat -d 2>/dev/null | grep -E "CustomPushNotification: onReceived" | tail -3
else
  bad "khong co log nao — KHONG co push nao den thiet bi"
fi

hdr "7. Trang thai app da cache"
adb exec-out run-as "$PKG" cat "files/databases/$(printf '%s' "$SERVER" | base64).db" > /tmp/pd_srv.db 2>/dev/null
PV=$(sqlite3 /tmp/pd_srv.db "select value from System where id='pushVerificationStatus';" 2>/dev/null | tr -d '"')
echo "  pushVerificationStatus = ${PV:-<chua co>}"
if [ "$PV" = "not_available" ]; then
  warn "app da cache trang thai nay va SE KHONG kiem tra lai (verifyPushProxy early-return)."
  warn "Sau khi sua push proxy: logout/login hoac xoa du lieu app de app xac minh lai."
fi
ACK=$(sqlite3 /tmp/pd_app.db "select id from Global where id like 'pushDisabledAck%';" 2>/dev/null)
[ -n "$ACK" ] && warn "da bam OK cho canh bao 'push disabled' -> canh bao se khong hien lai"

printf '\n'
