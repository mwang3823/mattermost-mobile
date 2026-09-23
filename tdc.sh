#!/usr/bin/env bash
#
# tdc.sh — bảng điều khiển terminal cho TDC Chat (Mattermost Mobile)
#
#   ./tdc.sh              mở giao diện
#   ./tdc.sh <lệnh>       chạy trực tiếp, không qua giao diện
#
# Điều hướng: mũi lên/xuống hoặc k/j, Enter để chọn, số/chữ bên trái để chọn nhanh,
#             q hoặc Esc để quay lại trang trước (mỗi trang cũng có mục "Thoát").
#
# Tương thích bash 3.2 (bản mặc định của macOS) — không dùng associative array.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
ROOT=$(pwd)

# Toàn bộ cấu hình build nằm trong assets/base/config.json (khối "Build").
# Các giá trị dưới đây chỉ là dự phòng khi chưa đọc được file đó.
CONFIG_FILE=assets/base/config.json
CONFIG_TOOL="node scripts/build_config.js"
PKG=com.thaiduongco.chat
ACTIVITY=com.mattermost.rnbeta.MainActivity
METRO_PORT=8081
TDC_GRADLE_ARGS=''
TDC_IOS_SIMULATOR=''
CONFIG_ERR=''

# Đọc config.json rồi đặt các biến TDC_* (xem "build_config.js --shell")
config_load() {
    CONFIG_ERR=''
    if ! command -v node >/dev/null 2>&1; then
        CONFIG_ERR='không tìm thấy node trong PATH'
        return 1
    fi
    local out
    if ! out=$($CONFIG_TOOL --shell 2>&1); then
        CONFIG_ERR=$(printf '%s' "$out" | tr -d '\033' | tail -3 | tr '\n' ' ')
        return 1
    fi
    eval "$out"
    PKG=$TDC_PKG
    ACTIVITY=$TDC_ACTIVITY
    METRO_PORT=$TDC_METRO_PORT
    return 0
}

# Giao diện dùng tiếng Việt có dấu nên cần locale UTF-8: terminal mới hiển thị
# đúng, và ${#chuỗi} mới đếm theo ký tự (dùng để canh lề) thay vì theo byte.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;;
    *)
        if locale -a 2>/dev/null | grep -qx 'en_US.UTF-8'; then
            export LC_CTYPE=en_US.UTF-8
        else
            export LC_CTYPE=UTF-8
        fi
        ;;
esac

# adb không luôn nằm trong PATH
if ! command -v adb >/dev/null 2>&1; then
    for p in "$HOME/Library/Android/sdk/platform-tools" "$HOME/Android/Sdk/platform-tools" \
             "${ANDROID_HOME:-}/platform-tools" "${ANDROID_SDK_ROOT:-}/platform-tools"; do
        [ -x "$p/adb" ] && PATH="$PATH:$p" && break
    done
fi
[ -d "$HOME/Library/Android/sdk/emulator" ] && PATH="$PATH:$HOME/Library/Android/sdk/emulator"
export PATH

# ---------------------------------------------------------------- trình bày
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
    RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'
    INV=$'\033[7m'
else
    B=''; DIM=''; R=''; RED=''; GRN=''; YLW=''; BLU=''; CYN=''; INV=''
fi

TTY_SAVED=''
tty_reset() {
    [ -n "$TTY_SAVED" ] && stty "$TTY_SAVED" 2>/dev/null
    TTY_SAVED=''
}
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
cleanup() { tty_reset; show_cursor; printf '\n'; }
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------ trạng thái
metro_pid()   { lsof -ti:"$METRO_PORT" 2>/dev/null | head -1; }
adb_devices() { command -v adb >/dev/null 2>&1 && adb devices 2>/dev/null | awk '/\tdevice$/{print $1}'; }
app_pid()     { command -v adb >/dev/null 2>&1 && adb shell pidof -s "$PKG" 2>/dev/null | tr -d '\r'; }

# Thanh trạng thái gọi lsof/adb/git nên KHÔNG tính lại mỗi lần vẽ — chỉ tính khi vào menu
# hoặc sau khi chạy xong một lệnh. Tính lại mỗi lần bấm phím vừa chậm vừa gây chớp.
STATUS_L1=''
STATUS_L2=''
status_refresh() {
    local name ver code branch metro devs rev
    name=${TDC_APP_NAME:-TDC Chat}
    ver=${TDC_VERSION:-?}
    code=${TDC_BUILD_NUMBER:-?}
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's|^heads/||' || echo '-')

    if [ -n "$(metro_pid)" ]; then metro="${GRN}Metro đang chạy${R}"; else metro="${DIM}Metro tắt${R}"; fi

    devs=$(adb_devices | tr '\n' ' ')
    if [ -n "$devs" ]; then devs="${GRN}${devs% }${R}"; else devs="${DIM}không có thiết bị${R}"; fi

    if command -v adb >/dev/null 2>&1 && adb reverse --list 2>/dev/null | grep -q "tcp:$METRO_PORT"; then
        rev="${GRN}đã reverse${R}"
    else
        rev="${YLW}chưa reverse${R}"
    fi

    STATUS_L1="${B}${CYN}  ${name}${R}  ${DIM}v${ver} (${code})  ${branch}${R}"
    STATUS_L2="  $metro  $devs  $rev"
    if [ -n "$CONFIG_ERR" ]; then
        STATUS_L2="$STATUS_L2  ${RED}config.json: ${CONFIG_ERR}${R}"
    fi
}

# ------------------------------------------------------------------ nhập phím
# Bash `read -sn1` gọi tcsetattr mỗi lần đọc; trên macOS việc đó LÀM MẤT các byte
# còn lại trong bộ đệm, nên mũi/Esc (3 byte) không bao giờ đọc đủ. Cách làm ở đây:
# đặt terminal sang chế độ cbreak MỘT LẦN cho cả vòng menu (vẫn giữ Ctrl+C), rồi đọc
# bằng `dd` — dd không đổi thuộc tính terminal nên cả chuỗi phím về trong 1 lần đọc.
tty_cbreak() {
    [ -t 0 ] || return 0
    TTY_SAVED=$(stty -g 2>/dev/null)
    stty -icanon -echo min 1 time 0 2>/dev/null
}

KEY=''
read_key() {
    local hex
    hex=$(dd bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$hex" in
        1b5b41)  KEY=up ;;
        1b5b42)  KEY=down ;;
        1b5b43)  KEY=right ;;
        1b5b44)  KEY=left ;;
        1b)      KEY=esc ;;
        0d|0a)   KEY=enter ;;
        03)      KEY=quit ;;          # Ctrl+C khi ISIG không bật
        '')      KEY=eof ;;
        *)
            if [ ${#hex} -eq 2 ]; then
                KEY=$(printf "\\x$hex")
            else
                KEY=other
            fi
            ;;
    esac
}

# Nhận phím tắt cho mục thứ i (0-based): 1..9 rồi a,b,c,...
# Bỏ j, k (đi lên/xuống) và q (quay lại) để không đụng phím điều hướng.
HOTKEY_LETTERS=abcdefghilmnoprstuvwxyz
hotkey_for() {
    if [ "$1" -lt 9 ]; then
        printf '%d' "$(($1 + 1))"
    else
        printf '%s' "${HOTKEY_LETTERS:$(($1 - 9)):1}"
    fi
}

# ------------------------------------------------------------------ menu
# choose <tiêu đề> <nhãn...>   -> đặt CHOICE = chỉ số (bắt đầu 0), hoặc -1 nếu huỷ
ITEM_ROW0=7
CHOICE=-1
LABEL_W=54
choose() {
    local title=$1; shift
    local -a items=("$@")
    local -a keys=()
    local n=${#items[@]}
    local cur=0 i slot

    local slot=0
    for ((i = 0; i < n; i++)); do
        if [ "${items[$i]}" = "-" ]; then
            keys+=(" ")
        else
            keys+=("$(hotkey_for "$slot")")
            slot=$((slot + 1))
        fi
    done

    # Dòng đầu tiên của danh sách mục (1-based), dùng cho việc vẽ lại từng dòng.
    local row0=$((ITEM_ROW0))

    # item_line <chỉ số> <1 nếu đang chọn>  -> in đúng một dòng, có \033[K để xoá phần dư.
    # Nhãn có dấu là UTF-8 nhiều byte nên KHÔNG dùng %-54s (printf canh theo byte,
    # lề sẽ lệch); đếm ký tự bằng ${#nhãn} rồi tự chèn khoảng trắng.
    item_line() {
        local idx=$1 selected=$2 k=${keys[$1]} label pad
        printf '\033[K'
        label=${items[$idx]}
        if [ "$label" = "-" ]; then
            printf '      %s%s%s' "$DIM" "······························" "$R"
        elif [ "$selected" -eq 1 ]; then
            pad=$((LABEL_W - ${#label}))
            [ "$pad" -lt 0 ] && pad=0
            printf '  %s %s  %s%*s %s' "$INV" "$k" "$label" "$pad" '' "$R"
        else
            printf '   %s%s%s  %s' "$DIM" "$k" "$R" "$label"
        fi
    }

    # Vẽ lại chỉ một dòng mục, đặt con trỏ tuyệt đối theo hàng
    redraw_one() {
        printf '\033[%d;1H' "$((row0 + $1))"
        item_line "$1" "$2"
    }

    # Vẽ toàn bộ. Dùng \033[H + \033[K từng dòng thay vì \033[2J: không có khung trống
    # nào ở giữa nên không bị chớp.
    full_draw() {
        printf '\033[H'
        printf '%s\033[K\n' "$STATUS_L1"
        printf '%s\033[K\n' "$STATUS_L2"
        printf '%s\033[K\n' "${DIM}  ────────────────────────────────────────────────────────────${R}"
        printf '\033[K\n'
        printf '  %s%s%s\033[K\n' "$B" "$title" "$R"
        printf '\033[K\n'
        local j
        for ((j = 0; j < n; j++)); do
            item_line "$j" "$([ "$j" -eq "$cur" ] && echo 1 || echo 0)"
            printf '\n'
        done
        printf '\033[K\n'
        printf '%s  mũi lên/xuống hoặc k/j · Enter để chọn · phím tắt bên trái · q quay lại%s\033[K\n' "$DIM" "$R"
        printf '\033[J'
    }

    local prev
    hide_cursor
    tty_cbreak
    status_refresh
    full_draw
    while :; do
        read_key
        case "$KEY" in
            up|k)
                prev=$cur
                cur=$((cur - 1)); [ "$cur" -lt 0 ] && cur=$((n - 1))
                [ "${items[$cur]}" = "-" ] && cur=$((cur - 1))
                [ "$cur" -lt 0 ] && cur=$((n - 1))
                redraw_one "$prev" 0
                redraw_one "$cur" 1
                ;;
            down|j)
                prev=$cur
                cur=$((cur + 1)); [ "$cur" -ge "$n" ] && cur=0
                [ "${items[$cur]}" = "-" ] && cur=$((cur + 1))
                [ "$cur" -ge "$n" ] && cur=0
                redraw_one "$prev" 0
                redraw_one "$cur" 1
                ;;
            enter)
                tty_reset; show_cursor; CHOICE=$cur; return 0 ;;
            q|esc|quit|eof)
                tty_reset; show_cursor; CHOICE=-1; return 0 ;;
            *)
                for ((i = 0; i < n; i++)); do
                    if [ "${items[$i]}" != "-" ] && [ "$KEY" = "${keys[$i]}" ]; then
                        tty_reset; show_cursor; CHOICE=$i; return 0
                    fi
                done
                ;;
        esac
    done
}

# choose_back <tiêu đề> <nhãn...>  — như choose nhưng tự thêm mục "Thoát" ở cuối trang.
# Chọn "Thoát" cho ra CHOICE = -1, giống hệt khi bấm q/Esc, nên các menu chỉ cần
# xử lý một trường hợp -1 và chỉ số của các mục còn lại không đổi.
choose_back() {
    local title=$1; shift
    local n=$#
    choose "$title" "$@" "-" "Thoát — về trang trước  (q)"
    [ "$CHOICE" -ge "$((n + 1))" ] && CHOICE=-1
    return 0
}

# Màn hình chờ sau khi chạy xong một lệnh: Enter, q hoặc Esc đều quay lại trang trước.
pause() {
    [ -t 0 ] || return 0
    printf '\n%s  Enter hoặc q để quay lại...%s' "$DIM" "$R"
    hide_cursor
    tty_cbreak
    while :; do
        read_key
        case "$KEY" in
            enter|q|esc|quit|eof) break ;;
        esac
    done
    tty_reset
    show_cursor
    printf '\n'
}

# Các nơi Gradle/Fastlane có thể để file sản phẩm
artifact_dirs() {
    local d
    for d in "$ROOT/android/app/build/outputs" "$ROOT/ios/build"; do
        [ -d "$d" ] && printf '%s\n' "$d"
    done
}

# find_artifacts [file mốc thời gian] -> liệt kê .apk/.aab/.ipa (mới hơn mốc nếu có)
find_artifacts() {
    local marker=${1:-} d
    local -a dirs=()
    while IFS= read -r d; do dirs+=("$d"); done < <(artifact_dirs)
    {
        if [ ${#dirs[@]} -gt 0 ]; then
            if [ -n "$marker" ]; then
                find "${dirs[@]}" -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) \
                     -newer "$marker" 2>/dev/null
            else
                find "${dirs[@]}" -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) 2>/dev/null
            fi
        fi
        # Fastlane di chuyển file đã build ra gốc dự án
        if [ -n "$marker" ]; then
            find "$ROOT" -maxdepth 1 -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) \
                 -newer "$marker" 2>/dev/null
        else
            find "$ROOT" -maxdepth 1 -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) 2>/dev/null
        fi
    } | sort -u
}

# print_artifacts [file mốc thời gian]
print_artifacts() {
    local f n=0 first='' sz
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ "$n" -eq 0 ]; then
            if [ -n "${1:-}" ]; then
                printf '\n%s  File vừa tạo:%s\n' "$B" "$R"
            else
                printf '\n%s  File đã build:%s\n' "$B" "$R"
            fi
        fi
        n=$((n + 1))
        [ -z "$first" ] && first=$f
        sz=$(du -h "$f" 2>/dev/null | cut -f1 | tr -d ' \t')
        printf '   %s%7s%s  %s\n' "$GRN" "${sz:-?}" "$R" "$(basename "$f")"
        printf '            %s%s%s\n' "$DIM" "$f" "$R"
    done < <(find_artifacts "${1:-}")

    if [ "$n" -eq 0 ]; then
        if [ -n "${1:-}" ]; then
            printf '\n%s  Không thấy file .apk/.aab/.ipa nào mới.%s\n' "$YLW" "$R"
            printf '%s  (Task này có thể chỉ build thư viện native, hoặc Fastlane đã chuyển file đi nơi khác)%s\n' "$DIM" "$R"
        else
            printf '%s  Chưa build gì — không có file .apk/.aab/.ipa nào.%s\n' "$DIM" "$R"
        fi
        return
    fi

    case "$first" in
        *.apk)
            printf '\n%s  Cài lên máy:%s  adb install -r "%s"\n' "$B" "$R" "$first" ;;
        *.aab)
            printf '\n%s  AAB dùng để tải lên Play Console; muốn cài trực tiếp thì dùng bundletool.%s\n' "$DIM" "$R" ;;
    esac
}

# _run <1 nếu cần liệt kê file sản phẩm> <mô tả> <lệnh...>
_run() {
    local want_artifacts=$1; shift
    local desc=$1; shift
    printf '\033[H\033[2J'
    printf '%s  %s%s\n' "${B}${CYN}" "$desc" "$R"
    local shown
    shown=$(printf '%s' "$*" | tr '\n' ' ' | tr -s ' ')
    [ ${#shown} -gt 92 ] && shown="${shown:0:89}..."
    printf '%s  $ %s%s\n\n' "$DIM" "$shown" "$R"

    local marker=''
    if [ "$want_artifacts" -eq 1 ]; then
        marker=$(mktemp -t tdcbuild 2>/dev/null) || marker=''
    fi

    local t0=$SECONDS
    "$@"
    local rc=$?
    local el=$((SECONDS - t0))
    printf '\n'
    if [ $rc -eq 0 ]; then
        printf '%s  ✓ xong trong %ds%s\n' "$GRN" "$el" "$R"
        [ "$want_artifacts" -eq 1 ] && print_artifacts "$marker"
    else
        printf '%s  ✗ thất bại (exit %d) sau %ds%s\n' "$RED" "$rc" "$el" "$R"
    fi
    [ -n "$marker" ] && rm -f "$marker"
    pause
}

# run <mô tả> <lệnh...>
run() { _run 0 "$@"; }

# ------------------------------------------------------------- cấu hình build
# Mọi lệnh build/chạy đều gọi hàm này trước: đọc assets/base/config.json và áp
# dụng xuống Gradle/Xcode/Info.plist/entitlements + sinh env cho Fastlane.
# Trả về 1 nếu cấu hình sai (không build tiếp).
apply_config() {
    if ! command -v node >/dev/null 2>&1; then
        printf '\n%s  Không tìm thấy node — không đọc được %s%s\n' "$RED" "$CONFIG_FILE" "$R"
        pause; return 1
    fi

    # Đã khớp thì đi tiếp ngay, không làm ồn
    if $CONFIG_TOOL --check >/dev/null 2>&1; then
        config_load
        return 0
    fi

    printf '\033[H\033[2J'
    printf '%s  Áp dụng cấu hình từ %s%s\n\n' "${B}${CYN}" "$CONFIG_FILE" "$R"
    if ! $CONFIG_TOOL --apply; then
        printf '\n%s  ✗ Cấu hình sai — không build.%s\n' "$RED" "$R"
        pause
        return 1
    fi
    config_load
    pause
    return 0
}

config_show()  { run "Cấu hình build (đọc $CONFIG_FILE)" $CONFIG_TOOL ; }
config_check() { run "Kiểm tra project so với $CONFIG_FILE" $CONFIG_TOOL --check ; }
config_apply() { run "Áp dụng $CONFIG_FILE xuống project" $CONFIG_TOOL --apply ; config_load ; }

config_edit() {
    local ed=${VISUAL:-${EDITOR:-}}
    if [ -z "$ed" ]; then
        if command -v nano >/dev/null 2>&1; then ed=nano; else ed=vi; fi
    fi
    tty_reset; show_cursor
    $ed "$CONFIG_FILE"
    if $CONFIG_TOOL --check >/dev/null 2>&1; then
        config_load
        return 0
    fi
    run "Áp dụng thay đổi vừa sửa" $CONFIG_TOOL --apply
    config_load
}

menu_config() {
    while :; do
        choose_back "Cấu hình build — $CONFIG_FILE" \
            "Xem toàn bộ cấu hình" \
            "Kiểm tra project có khớp cấu hình" \
            "Áp dụng cấu hình xuống project (+ env Fastlane)" \
            "-" \
            "Mở $CONFIG_FILE để sửa"
        case $CHOICE in
            -1) return ;;
            0) config_show ;;
            1) config_check ;;
            2) config_apply ;;
            4) config_edit ;;
        esac
    done
}

# run_build <mô tả> <lệnh...>   — như run, nhưng in đường dẫn file đã build khi xong
run_build() { _run 1 "$@"; }

need_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        printf '\n%s  Không tìm thấy adb. Thêm vào PATH:%s\n' "$RED" "$R"
        printf '    export PATH=$PATH:~/Library/Android/sdk/platform-tools\n'
        pause; return 1
    fi
    return 0
}

# Đặt DEV = serial thiết bị đã chọn (rỗng = để react-native tự chọn)
DEV=''
pick_device() {
    DEV=''
    need_adb || return 1
    local -a ds
    local d
    while IFS= read -r d; do [ -n "$d" ] && ds+=("$d"); done < <(adb_devices)
    if [ ${#ds[@]} -eq 0 ]; then
        printf '\n%s  Không có thiết bị/emulator nào đang chạy.%s\n\n' "$YLW" "$R"
        printf '  Khởi động máy ảo ngay? [%sY%s/n] ' "$B" "$R"
        local ans
        read -r ans </dev/tty
        case "$ans" in
            [nN]*) return 1 ;;
        esac
        avd_pick || return 1
        emulator_boot "$AVD" || { pause; return 1; }
        [ -z "$DEV" ] && DEV=$(adb_devices | head -1)
        if [ -z "$DEV" ]; then
            pause; return 1
        fi
        return 0
    fi
    if [ ${#ds[@]} -eq 1 ]; then DEV=${ds[0]}; return 0; fi
    choose_back "Chọn thiết bị" "${ds[@]}"
    [ "$CHOICE" -lt 0 ] && return 1
    DEV=${ds[$CHOICE]}
    return 0
}

# ---------------------------------------------------------- chạy & debug
metro_new_window() {
    if [ "$(uname)" = "Darwin" ]; then
        osascript -e "tell application \"Terminal\" to do script \"cd '$ROOT' && npm start\"" \
                  -e 'tell application "Terminal" to activate' >/dev/null
        printf '\n%s  Đã mở Metro ở cửa sổ Terminal mới.%s\n' "$GRN" "$R"
        printf '  Log JS hiện ở cửa sổ đó; nhấn %sj%s ở đó để mở React Native DevTools.\n' "$B" "$R"
    else
        printf '\n%s  Chỉ hỗ trợ mở cửa sổ mới trên macOS. Hãy chạy "npm start" ở terminal khác.%s\n' "$YLW" "$R"
    fi
    pause
}

metro_kill() {
    local p
    p=$(metro_pid)
    if [ -z "$p" ]; then
        printf '\n%s  Metro không chạy.%s\n' "$DIM" "$R"; pause; return
    fi
    run "Tắt Metro (pid $p)" bash -c "lsof -ti:$METRO_PORT | xargs kill -9"
}

# --------------------------------------------------------- máy ảo Android
AVD=''
avd_pick() {
    AVD=''
    if ! command -v emulator >/dev/null 2>&1; then
        printf '\n%s  Không tìm thấy lệnh "emulator". Thêm vào PATH:%s\n' "$RED" "$R"
        printf '    export PATH=$PATH:~/Library/Android/sdk/emulator\n'
        pause; return 1
    fi
    local -a avds
    local a
    while IFS= read -r a; do [ -n "$a" ] && avds+=("$a"); done < <(emulator -list-avds 2>/dev/null)
    if [ ${#avds[@]} -eq 0 ]; then
        printf '\n%s  Chưa có máy ảo nào.%s Tạo ở Android Studio: Device Manager → Create Device.\n' "$YLW" "$R"
        pause; return 1
    fi
    if [ ${#avds[@]} -eq 1 ]; then AVD=${avds[0]}; return 0; fi
    choose_back "Chọn máy ảo" "${avds[@]}"
    [ "$CHOICE" -lt 0 ] && return 1
    AVD=${avds[$CHOICE]}
    return 0
}

# Bật máy ảo rồi chờ Android khởi động xong. Chỉ chờ đúng serial mới xuất hiện
# để không nhầm với thiết bị đang cắm sẵn. Đặt DEV nếu thành công.
emulator_boot() {
    local avd=$1 before s new waited=0
    before=" $(adb_devices | tr '\n' ' ')"
    printf '  Đang bật %s%s%s — cửa sổ máy ảo sẽ hiện ra...\n' "$B" "$avd" "$R"
    nohup emulator -avd "$avd" >/dev/null 2>&1 &
    disown 2>/dev/null
    while [ $waited -lt 240 ]; do
        new=''
        for s in $(adb devices 2>/dev/null | awk '/\t(device|offline)$/{print $1}'); do
            case "$before" in *" $s "*) ;; *) new=$s ;; esac
        done
        if [ -n "$new" ] && [ "$(adb -s "$new" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
            adb -s "$new" shell input keyevent 82 >/dev/null 2>&1
            DEV=$new
            printf '  %sMáy ảo %s đã sẵn sàng (%ds).%s\n' "$GRN" "$new" "$waited" "$R"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
        printf '  %sđang chờ Android khởi động... %ds%s\r' "$DIM" "$waited" "$R"
    done
    printf '\n  %sChờ quá lâu — xem cửa sổ máy ảo xem có kẹt không.%s\n' "$YLW" "$R"
    return 1
}

emulator_start() {
    avd_pick || return 1
    printf '\033[H\033[2J'
    printf '%s  Khởi động máy ảo%s\n\n' "${B}${CYN}" "$R"
    emulator_boot "$AVD"
    pause
}

ios_sim_open() {
    ios_sim_pick || return
    run "Mở simulator \"$SIM\"" bash -c "
        xcrun simctl boot '$SIM' 2>/dev/null
        open -a Simulator
        echo 'Đã mở $SIM.'"
}

android_run() {
    pick_device || return
    need_adb || return
    adb -s "$DEV" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null 2>&1
    run "Build + cài đặt lên $DEV" npm run android -- --deviceId="$DEV"
}

android_open() {
    pick_device || return
    adb -s "$DEV" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null 2>&1
    run "Mở app trên $DEV (không build)" \
        adb -s "$DEV" shell am start -n "$PKG/$ACTIVITY"
}

# ------------------------------------------------- log gỡ lỗi (TDCDBG)
# App in ra các dòng "TDCDBG NAV/API/WS ..." khi chạy debug (app/utils/dev_trace.ts).
# Hàm này lọc và tô màu: NAV xanh dương, API 2xx/3xx xanh lá, API lỗi đỏ, WS vàng.
trace_colorize() {
    awk -v nav=$'\033[36m' -v ok=$'\033[32m' -v err=$'\033[31m' -v ws=$'\033[33m' -v dim=$'\033[2m' -v rst=$'\033[0m' '
        /TDCDBG/ {
            sub(/^.*TDCDBG /, "");
            if ($0 ~ /^ /) {
                # dòng req.headers/req.body/res.headers/res.body
                if (ENVIRON["TDC_TRACE_SHORT"] != "") { next }
                c = dim;
            }
            else if ($0 ~ /^NAV/)                   { c = nav }
            else if ($0 ~ /^WS/)                    { c = ws  }
            else if ($0 ~ /(ERR| [45][0-9][0-9] )/) { c = err }
            else                                    { c = ok  }
            printf "%s%s%s\n", c, $0, rst;
            fflush();
        }'
}

trace_header() {
    printf '%s  NAV%s màn hình   %sAPI%s request   %sWS%s websocket   %sheader/body%s   %sCtrl+C để dừng%s\n' \
        "$CYN" "$R" "$GRN" "$R" "$YLW" "$R" "$DIM" "$R" "$DIM" "$R"
    printf '%s  Ẩn header/body: TDC_TRACE_SHORT=1 ./tdc.sh trace   ·   trong app: tdcTrace({body:false})%s\n\n' "$DIM" "$R"
}

# Bộ xem log có gập/mở từng mục (scripts/trace_viewer.mjs). Đặt TDC_TRACE_PLAIN=1
# để quay về dạng text chạy thẳng.
android_trace() {
    pick_device || return
    if [ -n "${TDC_TRACE_PLAIN:-}" ]; then
        run "Log gỡ lỗi (text) trên $DEV" bash -c "
            $(declare -f trace_colorize trace_header)
            trace_header
            adb -s '$DEV' logcat -v brief '*:S' ReactNativeJS:V | trace_colorize"
        return
    fi
    run "Log gỡ lỗi trên $DEV" bash -c "
        adb -s '$DEV' logcat -v brief '*:S' ReactNativeJS:V | node '$ROOT/scripts/trace_viewer.mjs'"
}

ios_trace() {
    run "Log gỡ lỗi trên iOS simulator" bash -c "
        xcrun simctl spawn booted log stream --style compact \
            --predicate 'eventMessage CONTAINS \"TDCDBG\"' | node '$ROOT/scripts/trace_viewer.mjs'"
}

# Build + cài + mở, rồi bám luôn vào log gỡ lỗi
android_run_trace() {
    pick_device || return
    need_adb || return
    adb -s "$DEV" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null 2>&1
    run "Build + cài + log gỡ lỗi trên $DEV" bash -c "
        npm run android -- --deviceId='$DEV' || exit 1
        adb -s '$DEV' logcat -c
        adb -s '$DEV' logcat -v brief '*:S' ReactNativeJS:V | node '$ROOT/scripts/trace_viewer.mjs'"
}

# Trỏ toàn bộ traffic của máy ảo qua Proxyman/Charles để xem header + body dạng GUI.
# App tin CA do người dùng cài (android/app/src/main/res/xml/network_security_config.xml)
# nên chỉ cần cài chứng chỉ của proxy vào máy ảo là đọc được HTTPS.
device_proxy() {
    local target=$1
    pick_device || return
    if [ "$target" = "off" ]; then
        run "Tắt proxy trên $DEV" bash -c "
            adb -s '$DEV' shell settings put global http_proxy :0
            adb -s '$DEV' shell am force-stop '$PKG'
            echo 'Đã tắt proxy — mở lại app để áp dụng.'"
    else
        run "Proxy $target trên $DEV" bash -c "
            adb -s '$DEV' shell settings put global http_proxy '$target'
            adb -s '$DEV' shell am force-stop '$PKG'
            echo 'Đã trỏ traffic qua $target — mở lại app.'
            echo 'Chưa thấy HTTPS? Cài chứng chỉ CA của Proxyman/Charles vào máy ảo trước.'"
    fi
}

proxy_prompt() {
    printf '\033[H\033[2J'
    printf '%s  Bắt HTTPS qua proxy%s\n\n' "${B}${CYN}" "$R"
    printf '  Máy ảo gọi về máy Mac bằng %s10.0.2.2%s. Proxyman: 9090, Charles: 8888.\n' "$B" "$R"
    printf '  Địa chỉ proxy [10.0.2.2:9090]: '
    local target
    read -r target </dev/tty
    device_proxy "${target:-10.0.2.2:9090}"
}

android_reverse() {
    pick_device || return
    run "adb reverse tcp:$METRO_PORT" adb -s "$DEV" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT"
}

ios_sim_pick() {
    local -a sims
    local line
    # Mỗi dòng simctl: "    <tên> (<UDID 36 ký tự>) (<trạng thái>)" — tên iPad có thể
    # chứa dấu ngoặc, nên cắt từ phải sang bằng cách neo vào UDID.
    while IFS= read -r line; do [ -n "$line" ] && sims+=("$line"); done < <(
        xcrun simctl list devices available 2>/dev/null |
            sed -n 's/^ *\(.*\) (\([0-9A-F-]\{36\}\)) (\(.*\))[[:space:]]*$/\1 | \3/p' |
            grep -E '^(iPhone|iPad)' | head -25
    )
    if [ ${#sims[@]} -eq 0 ]; then
        printf '\n%s  Không liệt kê được simulator (cần Xcode).%s\n' "$YLW" "$R"; pause; return 1
    fi
    choose_back "Chọn iOS simulator" "${sims[@]}"
    [ "$CHOICE" -lt 0 ] && return 1
    SIM=$(printf '%s' "${sims[$CHOICE]}" | sed 's/ *|.*//' | sed 's/ *$//')
    return 0
}

# Liệt kê iPhone/iPad đang kết nối. Máy đã rút cáp/khoá vẫn hiện trong Xcode nhưng
# build xong mới fail ở bước cài (xcodebuild code 70), nên chỉ cho chọn máy nối được.
IOSDEV=''
IOSDEV_NAME=''

# In "trạng thái|tên|udid" cho từng thiết bị (trạng thái: connected/…)
ios_devices() {
    local json
    json=$(mktemp -t tdcdev) || return 1
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
    python3 - "$json" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for x in d.get('result', {}).get('devices', []):
    cp = x.get('connectionProperties', {})
    dp = x.get('deviceProperties', {})
    hp = x.get('hardwareProperties', {})
    print('|'.join([
        cp.get('tunnelState', '?'),
        '%s (iOS %s)' % (dp.get('name', '?'), dp.get('osVersionNumber', '?')),
        hp.get('udid', ''),
    ]))
PYEOF
    rm -f "$json"
}

ios_device_pick() {
    IOSDEV=''
    local -a names udids
    local line state name udid
    while IFS='|' read -r state name udid; do
        [ -n "$udid" ] || continue
        [ "$state" = connected ] || continue
        names+=("$name")
        udids+=("$udid")
    done < <(ios_devices)

    if [ ${#names[@]} -eq 0 ]; then
        printf '\n%s  Không có iPhone/iPad nào đang kết nối.%s\n\n' "$YLW" "$R"
        printf '  Cắm cáp (hoặc bật Wi-Fi sync), %smở khoá máy%s rồi bấm "Tin cậy" nếu máy hỏi.\n\n' "$B" "$R"
        printf '  Thiết bị Xcode đang biết:\n'
        while IFS='|' read -r state name udid; do
            [ -n "$udid" ] || continue
            printf '    %s%-28s%s %s%s%s\n' "$B" "$name" "$R" "$DIM" "$state" "$R"
        done < <(ios_devices)
        pause; return 1
    fi

    choose_back "Chọn thiết bị iOS" "${names[@]}"
    [ "$CHOICE" -lt 0 ] && return 1
    IOSDEV=${udids[$CHOICE]}
    IOSDEV_NAME=${names[$CHOICE]}
    return 0
}

ios_run_device() {
    ios_device_pick || return
    run "Chạy iOS trên \"$IOSDEV_NAME\"" npm run ios -- --udid "$IOSDEV"
}

ios_run_pick() {
    ios_sim_pick || return
    run "Chạy iOS trên \"$SIM\"" npm run ios -- --simulator="$SIM"
}

# Build.Ios.defaultSimulator trong config.json; để trống thì Xcode tự chọn
ios_run_default() {
    if [ -n "$TDC_IOS_SIMULATOR" ]; then
        run "Chạy iOS trên \"$TDC_IOS_SIMULATOR\" (config.json)" \
            npm run ios -- --simulator="$TDC_IOS_SIMULATOR"
    else
        run "Chạy iOS (simulator mặc định)" npm run ios
    fi
}

# Archive thẳng bằng xcodebuild. Kết quả đặt trong thư mục Archives của Xcode
# nên mở Window > Organizer là thấy ngay để Distribute App.
ARCHIVE_PATH=''

# Cài Pods nếu thiếu/cũ hơn Podfile.lock
ios_pods_ready() {
    if [ -d "$ROOT/ios/Pods" ] && [ ! "$ROOT/ios/Podfile.lock" -nt "$ROOT/ios/Pods" ]; then
        return 0
    fi
    printf '  %sPods chưa cài hoặc đã cũ — chạy pod install...%s\n\n' "$YLW" "$R"
    npm run pod-install || return 1
    printf '\n'
    return 0
}

# Đặt ARCHIVE_PATH = ~/Library/Developer/Xcode/Archives/<ngày>/<tên>.xcarchive
ios_archive_path() {
    local day dir name
    day=$(date '+%Y-%m-%d')
    name="${TDC_IOS_APP_NAME:-${TDC_APP_NAME:-Mattermost}} ${TDC_VERSION:-0} ($(date '+%H-%M'))"
    dir="$HOME/Library/Developer/Xcode/Archives/$day"
    mkdir -p "$dir" || return 1
    ARCHIVE_PATH="$dir/$name.xcarchive"
    return 0
}

ios_archive_exec() {
    ( cd "$ROOT/ios" && xcodebuild \
        -workspace Mattermost.xcworkspace \
        -scheme Mattermost \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates \
        archive )
}

ios_archive_info() {
    printf '  %sPhiên bản%s  %s (build %s)\n' "$DIM" "$R" "${TDC_VERSION:-?}" "${TDC_BUILD_NUMBER:-?}"
    printf '  %sBundle ID%s  %s\n' "$DIM" "$R" "${TDC_IOS_BUNDLE_ID:-${TDC_PKG:-?}}"
    printf '  %sArchive%s    %s\n\n' "$DIM" "$R" "$ARCHIVE_PATH"
    printf '  %sXong thì mở Xcode > Window > Organizer để Distribute App.%s\n' "$DIM" "$R"
}

ios_archive() {
    printf '\033[H\033[2J'
    printf '%s  Archive iOS (xcodebuild)%s\n\n' "${B}${CYN}" "$R"
    ios_pods_ready || { printf '\n%s  ✗ pod install thất bại.%s\n' "$RED" "$R"; pause; return 1; }
    ios_archive_path || { printf '\n%s  ✗ không tạo được thư mục Archives.%s\n' "$RED" "$R"; pause; return 1; }
    ios_archive_info
    run "xcodebuild archive" ios_archive_exec
    [ -d "$ARCHIVE_PATH" ]
}

# Chuẩn bị project rồi mở Xcode để tự Product > Archive.
# Không build IPA ở đây: cấu hình (bundle id, version, build number, entitlements)
# đã được apply_config ghi xuống project nên Xcode archive là khớp config.json.
ios_xcode_archive() {
    printf '\033[H\033[2J'
    printf '%s  Chuẩn bị iOS để archive bằng Xcode%s\n\n' "${B}${CYN}" "$R"

    ios_pods_ready || { printf '\n%s  ✗ pod install thất bại.%s\n' "$RED" "$R"; pause; return 1; }

    printf '  %sPhiên bản%s  %s (build %s)\n' "$DIM" "$R" "${TDC_VERSION:-?}" "${TDC_BUILD_NUMBER:-?}"
    printf '  %sBundle ID%s  %s\n\n' "$DIM" "$R" "${TDC_IOS_BUNDLE_ID:-${TDC_PKG:-?}}"

    printf '  Trong Xcode:\n'
    printf '    1. Chọn scheme %sMattermost%s, thiết bị %sAny iOS Device (arm64)%s\n' "$B" "$R" "$B" "$R"
    printf '    2. %sProduct > Archive%s\n' "$B" "$R"
    printf '    3. %sDistribute App%s trong Organizer\n\n' "$B" "$R"
    printf '  %sLưu ý: tắt Metro trước khi archive (Release tự bundle JS).%s\n\n' "$DIM" "$R"

    run "Mở ios/Mattermost.xcworkspace" open "$ROOT/ios/Mattermost.xcworkspace"
}

menu_debug() {
    while :; do
        choose_back "Chạy & Debug" \
            "Khởi động Metro ở cửa sổ Terminal mới" \
            "Metro ở cửa sổ này (xoá cache)" \
            "Tắt Metro (port $METRO_PORT)" \
            "-" \
            "Android: khởi động máy ảo..." \
            "Android: build + cài đặt + mở" \
            "Android: build + cài đặt + mở + log gỡ lỗi  ← màn hình, API, WS" \
            "Android: chỉ mở app (không build)" \
            "Android: xem log gỡ lỗi (app đang chạy)" \
            "Android: log gỡ lỗi dạng text (không gập/mở)" \
            "Android: adb reverse $METRO_PORT" \
            "Android: mở dev menu" \
            "-" \
            "Android: bắt HTTPS qua Proxyman/Charles..." \
            "Android: tắt proxy" \
            "-" \
            "iOS: mở simulator..." \
            "iOS: chạy trên simulator mặc định" \
            "iOS: chọn simulator rồi chạy" \
            "iOS: chạy trên thiết bị thật" \
            "iOS: xem log gỡ lỗi (simulator)"
        case $CHOICE in
            -1) return ;;
            0) apply_config && metro_new_window ;;
            1) apply_config && run "Metro (xoá cache) — Ctrl+C để dừng" npm start -- --reset-cache ;;
            2) metro_kill ;;
            4) emulator_start ;;
            5) apply_config && android_run ;;
            6) apply_config && android_run_trace ;;
            7) android_open ;;
            8) android_trace ;;
            9) TDC_TRACE_PLAIN=1 TDC_TRACE_SHORT=1 android_trace ;;
            10) android_reverse ;;
            11) pick_device && run "Mở dev menu trên $DEV" adb -s "$DEV" shell input keyevent 82 ;;
            13) proxy_prompt ;;
            14) device_proxy off ;;
            16) ios_sim_open ;;
            17) apply_config && ios_run_default ;;
            18) apply_config && ios_run_pick ;;
            19) apply_config && ios_run_device ;;
            20) ios_trace ;;
        esac
    done
}

# ----------------------------------------------------------------- build
gradlew() {
    local task=$1; shift
    # Thông tin ký (nếu khai trong config.json) đã được export dưới dạng
    # ORG_GRADLE_PROJECT_* lúc đọc cấu hình, Gradle tự nhận nên không cần -P.
    run_build "Gradle: $task" bash -c "cd '$ROOT/android' && ./gradlew $task"
}

list_artifacts() {
    printf '\033[H\033[2J'
    printf '%s  File đã build%s\n\n' "${B}${CYN}" "$R"
    local f n=0 sz
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        sz=$(du -h "$f" 2>/dev/null | cut -f1 | tr -d ' \t')
        printf '   %s%7s%s  %s\n' "$GRN" "${sz:-?}" "$R" "$(basename "$f")"
        printf '            %s%s%s\n' "$DIM" "$f" "$R"
        printf '            %s%s%s\n' "$DIM" "$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)" "$R"
    done < <(find_artifacts)
    [ "$n" -eq 0 ] && printf '   %schưa build gì%s\n' "$DIM" "$R"
    pause
}

menu_build() {
    while :; do
        choose_back "Build" \
            "APK debug        (gradlew assembleDebug)" \
            "APK release      (gradlew assembleRelease)" \
            "AAB release      (gradlew bundleRelease)  ← lên Play Store" \
            "-" \
            "APK release chỉ arm64-v8a  ← nhanh ~3x, đủ cho máy thật" \
            "APK debug   chỉ arm64-v8a" \
            "-" \
            "APK qua Fastlane (npm run build:android)" \
            "APK chưa ký      (npm run build:android-unsigned)" \
            "AAB qua Fastlane (ANDROID_BUILD_TASK=bundle)" \
            "-" \
            "iOS cho simulator (npm run build:ios-sim)" \
            "iOS: Archive luôn (xcodebuild) → Organizer  ← IPA lên App Store" \
            "iOS: chỉ chuẩn bị + mở Xcode để tự Archive" \
            "-" \
            "Xem các file đã build"
        case $CHOICE in
            -1) return ;;
            0) apply_config && gradlew "app:assembleDebug" ;;
            1) apply_config && gradlew "app:assembleRelease" ;;
            2) apply_config && gradlew "app:bundleRelease" ;;
            4) apply_config && gradlew "app:assembleRelease -PreactNativeArchitectures=arm64-v8a" ;;
            5) apply_config && gradlew "app:assembleDebug -PreactNativeArchitectures=arm64-v8a" ;;
            7) apply_config && run_build "Fastlane: APK" npm run build:android ;;
            8) apply_config && run_build "Fastlane: APK chưa ký" npm run build:android-unsigned ;;
            9) apply_config && run_build "Fastlane: AAB" env ANDROID_BUILD_TASK=bundle npm run build:android ;;
            11) apply_config && run_build "iOS cho simulator" npm run build:ios-sim ;;
            12) apply_config && ios_archive ;;
            13) apply_config && ios_xcode_archive ;;
            15) list_artifacts ;;
        esac
    done
}

# ---------------------------------------------------------------- kiểm tra
test_pattern() {
    printf '\033[H\033[2J'
    printf '%s  Chạy test theo pattern%s\n\n' "${B}${CYN}" "$R"
    printf '  Ví dụ: %sapp/queries/servers/channel.test.ts%s hoặc %sedit_profile%s\n\n' "$B" "$R" "$B" "$R"
    printf '  Pattern (để trống để quay lại): '
    local pat
    read -r pat </dev/tty
    [ -z "$pat" ] && return
    run "npm test -- $pat" npm test -- "$pat"
}

menu_check() {
    while :; do
        choose_back "Kiểm tra" \
            "check       lint + tsc  (chạy trước khi commit)" \
            "check-test  lint + tsc + jest" \
            "-" \
            "lint" \
            "fix         eslint --fix" \
            "tsc         tsc --noEmit" \
            "-" \
            "test        toàn bộ jest" \
            "test theo pattern..." \
            "test:watch" \
            "test:coverage" \
            "-" \
            "i18n check  (vi.json so với en.json)"
        case $CHOICE in
            -1) return ;;
            0) run "npm run check" npm run check ;;
            1) run "npm run check-test" npm run check-test ;;
            3) run "npm run lint" npm run lint ;;
            4) run "npm run fix" npm run fix ;;
            5) run "npm run tsc" npm run tsc ;;
            7) run "npm test" npm test ;;
            8) test_pattern ;;
            9) run "npm run test:watch — Ctrl+C để dừng" npm run test:watch ;;
            10) run "npm run test:coverage" npm run test:coverage ;;
            12) run "i18n check" python3 scripts/i18n_check.py ;;
        esac
    done
}

# ------------------------------------------------------------ thiết bị & log
menu_log() {
    while :; do
        choose_back "Thiết bị & Log" \
            "Danh sách thiết bị" \
            "Danh sách AVD (emulator)" \
            "Khởi động máy ảo..." \
            "-" \
            "Log gỡ lỗi TDC  (màn hình + API + WS)" \
            "Log JS          (ReactNativeJS)" \
            "Log toàn bộ app (theo pid)" \
            "Log push notification" \
            "Log 200 dòng gần nhất rồi thoát" \
            "Xoá buffer logcat" \
            "-" \
            "Log iOS simulator" \
            "-" \
            "Chụp ảnh màn hình" \
            "Buộc dừng app" \
            "Gỡ app (mất session + DB)"
        case $CHOICE in
            -1) return ;;
            0) need_adb && run "adb devices" adb devices -l ;;
            1) run "emulator -list-avds" bash -c "emulator -list-avds 2>/dev/null || echo 'không tìm thấy emulator trong PATH'" ;;
            2) emulator_start ;;
            4) android_trace ;;
            5) pick_device && run "Log JS — Ctrl+C để dừng" adb -s "$DEV" logcat "*:S" ReactNativeJS:V ;;
            6) pick_device && run "Log toàn bộ app — Ctrl+C để dừng" \
                   bash -c "p=\$(adb -s '$DEV' shell pidof -s $PKG | tr -d '\r'); \
                            if [ -z \"\$p\" ]; then echo 'app không chạy'; else adb -s '$DEV' logcat --pid=\$p; fi" ;;
            7) pick_device && run "Log push notification — Ctrl+C để dừng" \
                   bash -c "adb -s '$DEV' logcat | grep --line-buffered -E \
                     'PushNotifications\.|CustomPushNotification|ReactNativeNotifs|canReceiveNotifications|Notification token'" ;;
            8) pick_device && run "200 dòng log gần nhất" \
                   bash -c "adb -s '$DEV' logcat -d -t 200 '*:S' ReactNativeJS:V CustomPushNotification:V" ;;
            9) pick_device && run "Xoá buffer logcat" adb -s "$DEV" logcat -c ;;
            11) run "Log iOS — Ctrl+C để dừng" npx react-native log-ios ;;
            13) pick_device && run "Chụp ảnh màn hình" bash -c "
                    out='$ROOT/screenshot-\$(date +%Y%m%d-%H%M%S).png'
                    adb -s '$DEV' exec-out screencap -p > \"\$out\" && echo \"Đã lưu: \${out#$ROOT/}\"" ;;
            14) pick_device && run "Buộc dừng $PKG" adb -s "$DEV" shell am force-stop "$PKG" ;;
            15)
                pick_device || continue
                printf '\n%s  Gỡ app sẽ XOÁ session đăng nhập và toàn bộ DB trên máy.%s\n' "$YLW" "$R"
                printf '  Nhập %sgo%s để xác nhận: ' "$B" "$R"
                local c; read -r c </dev/tty
                [ "$c" = "go" ] && run "adb uninstall $PKG" adb -s "$DEV" uninstall "$PKG"
                ;;
        esac
    done
}

# ----------------------------------------------------------------- công cụ
# Gradle lưu đường dẫn TUYỆT ĐỐI tới CMakeLists.txt do codegen sinh ra trong node_modules.
# Nếu node_modules bị xoá/cài lại mà .cxx còn nguyên thì build thất bại với CXX1409:
#   expected buildFiles file '.../generated/source/codegen/jni/CMakeLists.txt' to exist
clear_cxx() {
    local sz
    sz=$(du -sh "$ROOT/android/app/.cxx" 2>/dev/null | cut -f1 | tr -d ' \t')
    if [ -z "$sz" ]; then
        printf '%s  android/app/.cxx không tồn tại — không cần xoá.%s\n' "$DIM" "$R"
        return 0
    fi
    printf '  Xoá android/app/.cxx (%s)...\n' "$sz"
    rm -rf "$ROOT/android/app/.cxx"
    printf '%s  Đã xoá. Lần build sau CMake sẽ cấu hình lại (chậm hơn một chút).%s\n' "$GRN" "$R"
}

env_doctor() {
    run "Thông tin môi trường" bash -c '
        # printf "%-16s" canh theo BYTE, nhãn có dấu là UTF-8 nhiều byte nên lề sẽ
        # lệch; tự chèn khoảng trắng theo số ký tự (${#nhãn}) thay cho %-16s.
        row() {
            local l=$1 pad
            pad=$((16 - ${#l})); [ "$pad" -lt 0 ] && pad=0
            printf "  %s%*s %s\n" "$l" "$pad" "" "${2:-<không có>}"
        }
        row "node"      "$(node -v 2>/dev/null)   (cần $(cat .nvmrc 2>/dev/null))"
        row "npm"       "$(npm -v 2>/dev/null)"
        row "ruby"      "$(ruby -v 2>/dev/null | cut -d" " -f2)   (cần $(cat .ruby-version 2>/dev/null))"
        row "java"      "$(java -version 2>&1 | head -1)"
        row "watchman"  "$(watchman -v 2>/dev/null)"
        row "xcodebuild" "$(xcodebuild -version 2>/dev/null | head -1)"
        row "adb"       "$(adb version 2>/dev/null | head -1)"
        row "bundler"   "$(bundle -v 2>/dev/null)"
        row "pod"       "$(pod --version 2>/dev/null)"
        echo
        row "git branch"       "$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed "s|^heads/||")"
        row "file thay đổi"    "$(git status --porcelain 2>/dev/null | wc -l | tr -d " ")"
        row "node_modules"     "$([ -d node_modules ] && echo có || echo "CHƯA CÀI")"
        row "ios/Pods"         "$([ -d ios/Pods ] && echo có || echo "CHƯA CÀI")"
        row "dist/assets"      "$([ -d dist/assets ] && echo có || echo "CHƯA SINH")"
        row "local.properties" "$([ -f android/local.properties ] && echo có || echo "không có")"
        row "firebase project" "$(python3 -c "import json;print(json.load(open(\"android/app/google-services.json\"))[\"project_info\"][\"project_id\"])" 2>/dev/null)"
    '
}

menu_tools() {
    while :; do
        choose_back "Công cụ dự án" \
            "Thông tin môi trường" \
            "-" \
            "Sửa lỗi build CXX1409 (xoá metadata CMake .cxx)" \
            "Chẩn đoán push notification (push_doctor.sh)" \
            "Sinh lại icon từ tdc_logo.png" \
            "Sinh lại splash cho bản release" \
            "Đồng bộ assets/base -> dist/assets" \
            "-" \
            "npm install" \
            "pod install" \
            "clean (xoá build artifacts)" \
            "Reset sâu: clean + node_modules + Pods" \
            "-" \
            "i18n-extract (sinh lại en.json từ code)"
        case $CHOICE in
            -1) return ;;
            0) env_doctor ;;
            2) run "Xoá metadata CMake (.cxx)" clear_cxx ;;
            3) run "push_doctor.sh" ./scripts/push_doctor.sh ;;
            4) run "Sinh lại icon" python3 scripts/gen_icons.py ;;
            5) run "Sinh lại splash release" python3 scripts/gen_release_splash.py ;;
            6) run "generate-assets" node scripts/generate-assets.js ;;
            8) run "npm install" npm install ;;
            9) run "pod install" npm run pod-install ;;
            10) run "npm run clean" npm run clean ;;
            11)
                printf '\n%s  Sẽ xoá node_modules, ios/Pods và build artifacts. Cài lại mất vài phút.%s\n' "$YLW" "$R"
                printf '  Nhập %sreset%s để xác nhận: ' "$B" "$R"
                local c; read -r c </dev/tty
                [ "$c" = "reset" ] && run "Reset sâu" bash -c "
                    npm run clean
                    watchman watch-del-all 2>/dev/null
                    rm -rf node_modules ios/Pods ios/Podfile.lock
                    rm -rf \"\$TMPDIR\"/metro-* \"\$TMPDIR\"/haste-map-* 2>/dev/null
                    npm install"
                ;;
            13) run "i18n-extract" npm run i18n-extract ;;
        esac
    done
}

# ------------------------------------------------------------------- chính
menu_main() {
    while :; do
        choose "Chọn việc cần làm" \
            "Chạy & Debug" \
            "Build  (APK / AAB / IPA)" \
            "Kiểm tra  (lint / tsc / test)" \
            "Thiết bị & Log" \
            "Cấu hình build  ($CONFIG_FILE)" \
            "Công cụ dự án" \
            "-" \
            "Thoát — đóng bảng điều khiển  (q)"
        case $CHOICE in
            -1|7) printf '\n'; exit 0 ;;
            0) menu_debug ;;
            1) menu_build ;;
            2) menu_check ;;
            3) menu_log ;;
            4) menu_config ;;
            5) menu_tools ;;
        esac
    done
}

# ------------------------------------------------------- gọi trực tiếp (CLI)
usage() {
    cat <<USAGE
${B}tdc.sh${R} — bảng điều khiển terminal cho TDC Chat

  ./tdc.sh                 mở giao diện
  ./tdc.sh <lệnh> [tham số]  chạy trực tiếp

Lệnh:
  ${B}apk${R}                    APK debug   (gradlew assembleDebug)
  ${B}apk-release${R}            APK release (gradlew assembleRelease)
  ${B}apk-arm64${R}              APK release chi arm64-v8a (nhanh ~3x, du cho may that)
  ${B}aab${R}                    AAB release (gradlew bundleRelease)
  ${B}archive${R}                archive iOS bằng xcodebuild vào thư mục Archives của Xcode
  ${B}xcode${R}                  áp cấu hình + mở Xcode để tự Product > Archive
  ${B}ios-sim${R}                build iOS cho simulator
  ${B}emulator [tên]${R}         bật máy ảo Android rồi chờ khởi động xong
  ${B}avds${R}                   liệt kê máy ảo Android đã tạo
  ${B}simulator [tên]${R}        mở iOS simulator
  ${B}android${R}                build + cài đặt + mở trên Android
  ${B}ios${R}                    chạy trên iOS simulator
  ${B}metro${R}                  khởi động Metro (xoá cache)
  ${B}android-log${R}            build + cài đặt + mở + bám log gỡ lỗi (Android)
  ${B}trace${R}                  log gỡ lỗi gập/mở được: màn hình + API + WebSocket (Android)
  ${B}trace-text${R}             log gỡ lỗi dạng text chạy thẳng
  ${B}trace-ios${R}              log gỡ lỗi trên iOS simulator
  ${B}proxy [host:port|off]${R}  trỏ máy ảo qua Proxyman/Charles để xem header + body
  ${B}log${R}                    xem log JS
  ${B}log-push${R}               xem log push notification
  ${B}check${R}                  lint + tsc
  ${B}test${R}                   jest
  ${B}doctor${R}                 thông tin môi trường
  ${B}push-doctor${R}            chẩn đoán push notification
  ${B}config${R}                 xem toàn bộ cấu hình build (assets/base/config.json)
  ${B}config-apply${R}           áp dụng cấu hình xuống project + sinh env Fastlane
  ${B}config-check${R}           kiểm tra project có khớp cấu hình (lệch thì exit 1)
  ${B}artifacts${R}              liệt kê các file .apk/.aab/.ipa đã build
  ${B}fix-cxx${R}                xoá metadata CMake (.cxx) khi gặp lỗi CXX1409
  ${B}help${R}                   màn hình này
USAGE
}

# Chạy lệnh build ở chế độ CLI rồi in đường dẫn file sản phẩm
direct_build() {
    local marker rc
    marker=$(mktemp -t tdcbuild 2>/dev/null) || marker=''
    "$@"; rc=$?
    if [ $rc -eq 0 ]; then
        print_artifacts "$marker"
        printf '\n'
    fi
    [ -n "$marker" ] && rm -f "$marker"
    return $rc
}

# Đọc + áp dụng config.json trước khi build/chạy ở chế độ CLI
direct_config() {
    command -v node >/dev/null 2>&1 || {
        printf '%sKhông tìm thấy node — không đọc được %s%s\n' "$RED" "$CONFIG_FILE" "$R"
        exit 1
    }
    $CONFIG_TOOL --apply || exit 1
    config_load
}

direct() {
    case $1 in
        apk|apk-release|apk-arm64|aab|archive|xcode|ios-sim|android|android-log|ios|metro) direct_config ;;
    esac
    case $1 in
        apk)         direct_build bash -c "cd '$ROOT/android' && ./gradlew app:assembleDebug" ;;
        apk-release) direct_build bash -c "cd '$ROOT/android' && ./gradlew app:assembleRelease" ;;
        apk-arm64)   direct_build bash -c "cd '$ROOT/android' && ./gradlew app:assembleRelease -PreactNativeArchitectures=arm64-v8a" ;;
        aab)         direct_build bash -c "cd '$ROOT/android' && ./gradlew app:bundleRelease" ;;
        archive)     trap - EXIT
                     ios_pods_ready || exit 1
                     ios_archive_path || exit 1
                     ios_archive_info
                     ios_archive_exec || exit 1
                     printf '\n%s  ✓ %s%s\n' "$GRN" "$ARCHIVE_PATH" "$R"
                     open -R "$ARCHIVE_PATH" ;;
        xcode)       trap - EXIT
                     [ -d "$ROOT/ios/Pods" ] || npm run pod-install || exit 1
                     open "$ROOT/ios/Mattermost.xcworkspace" ;;
        ios-sim)     direct_build npm run build:ios-sim ;;
        android)     npm run android ;;
        ios)         npm run ios ;;
        metro)       npm start -- --reset-cache ;;
        android-log) trap - EXIT; need_adb || exit 1
                     adb reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null 2>&1
                     npm run android || exit 1
                     adb logcat -c
                     adb logcat -v brief "*:S" ReactNativeJS:V | node "$ROOT/scripts/trace_viewer.mjs" ;;
        emulator)    trap - EXIT; need_adb || exit 1
                     if [ -n "${2:-}" ]; then AVD=$2; else avd_pick || exit 1; fi
                     emulator_boot "$AVD" ;;
        avds)        trap - EXIT
                     emulator -list-avds 2>/dev/null || { echo 'không tìm thấy emulator trong PATH'; exit 1; } ;;
        simulator)   trap - EXIT
                     if [ -n "${2:-}" ]; then SIM=$2; else ios_sim_pick || exit 1; fi
                     xcrun simctl boot "$SIM" 2>/dev/null
                     open -a Simulator
                     echo "Đã mở $SIM." ;;
        proxy)       trap - EXIT; need_adb || exit 1
                     if [ "${2:-}" = "off" ]; then
                         adb shell settings put global http_proxy :0
                         echo 'Đã tắt proxy — mở lại app để áp dụng.'
                     else
                         adb shell settings put global http_proxy "${2:-10.0.2.2:9090}"
                         echo "Đã trỏ traffic qua ${2:-10.0.2.2:9090} — mở lại app."
                     fi
                     adb shell am force-stop "$PKG" ;;
        trace)       trap - EXIT; need_adb || exit 1
                     adb logcat -v brief "*:S" ReactNativeJS:V | node "$ROOT/scripts/trace_viewer.mjs" ;;
        trace-text)  trap - EXIT; need_adb || exit 1
                     trace_header
                     adb logcat -v brief "*:S" ReactNativeJS:V | trace_colorize ;;
        trace-ios)   trap - EXIT
                     xcrun simctl spawn booted log stream --style compact \
                         --predicate 'eventMessage CONTAINS "TDCDBG"' | node "$ROOT/scripts/trace_viewer.mjs" ;;
        log)         need_adb && adb logcat "*:S" ReactNativeJS:V ;;
        log-push)    need_adb && adb logcat | grep --line-buffered -E \
                         'PushNotifications\.|CustomPushNotification|ReactNativeNotifs|canReceiveNotifications|Notification token' ;;
        check)       npm run check ;;
        test)        npm test ;;
        doctor)      trap - EXIT; env_doctor ;;
        push-doctor) ./scripts/push_doctor.sh ;;
        artifacts)   trap - EXIT; print_artifacts ;;
        fix-cxx)     clear_cxx ;;
        config)       trap - EXIT; $CONFIG_TOOL ;;
        config-apply) trap - EXIT; $CONFIG_TOOL --apply ;;
        config-check) trap - EXIT; $CONFIG_TOOL --check ;;
        help|-h|--help) usage ;;
        *) printf '%sLệnh không hợp lệ: %s%s\n\n' "$RED" "$1" "$R"; usage; exit 1 ;;
    esac
}

if [ $# -gt 0 ]; then
    trap - EXIT
    direct "$@"
else
    # Nạp cấu hình để menu/thanh trạng thái dùng đúng giá trị trong config.json
    config_load || true
    if [ ! -t 0 ]; then
        printf '%sCần terminal tương tác. Dùng "./tdc.sh help" để xem các lệnh trực tiếp.%s\n' "$YLW" "$R"
        exit 1
    fi
    menu_main
fi
