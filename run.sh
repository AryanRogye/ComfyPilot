#!/bin/zsh
# ╔════════════════════════════════════════╗
# ║         ComfyPilot Monitor v1.0        ║
# ╚════════════════════════════════════════╝
# Drop this next to your build script.
# Usage: ./comfy_monitor.sh [PID]
#   or let it build + launch for you.

# ── Config ──────────────────────────────────────────────────────────────────
PROJECT="ComfyPilot.xcodeproj"
SCHEME="ComfyPilot"
CONFIG="Debug"
DERIVED="./.derived"
APP_PATH="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
EXEC="$APP_PATH/Contents/MacOS/$SCHEME"

REFRESH=1          # seconds between updates
HISTORY_LEN=20     # sparkline history width

# ── Colors (ANSI) ────────────────────────────────────────────────────────────
R=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'

BG_DARK=$'\e[48;5;234m'
BG_PANEL=$'\e[48;5;236m'
BG_HEADER=$'\e[48;5;17m'

FG_WHITE=$'\e[97m'
FG_TITLE=$'\e[38;5;75m'      # light blue
FG_LABEL=$'\e[38;5;245m'     # gray
FG_VALUE=$'\e[38;5;231m'     # bright white
FG_GREEN=$'\e[38;5;82m'
FG_YELLOW=$'\e[38;5;220m'
FG_RED=$'\e[38;5;196m'
FG_CYAN=$'\e[38;5;87m'
FG_ORANGE=$'\e[38;5;214m'
FG_PURPLE=$'\e[38;5;141m'
FG_DIM=$'\e[38;5;240m'

# ── State ─────────────────────────────────────────────────────────────────────
cpu_history=()
mem_history=()
START_TIME=$(date +%s)
APP_PID=""

# ── Helpers ───────────────────────────────────────────────────────────────────

# move cursor to row,col (1-indexed)
move() { printf '\e[%d;%dH' "$1" "$2"; }

clear_screen() { printf '\e[2J\e[H'; }
hide_cursor()  { printf '\e[?25l'; }
show_cursor()  { printf '\e[?25h'; }

# pad/truncate string to exact width
fit() {
    local str="$1" width="$2"
    printf "%-${width}s" "${str:0:$width}"
}

# color-code a percentage
pct_color() {
    local pct="${1%.*}"   # integer part
    if   (( pct >= 80 )); then echo -n "$FG_RED"
    elif (( pct >= 50 )); then echo -n "$FG_YELLOW"
    else                       echo -n "$FG_GREEN"
    fi
}

# bar chart  ▏▎▍▌▋▊▉█
bar() {
    local pct="${1%.*}" width="${2:-20}"
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local col
    col=$(pct_color "$pct")
    printf '%s' "$col"
    printf '█%.0s' $(seq 1 $filled 2>/dev/null || true)
    printf '%s' "$FG_DIM"
    printf '░%.0s' $(seq 1 $empty 2>/dev/null || true)
    printf '%s' "$R"
}

# sparkline from array of 0-100 values
sparkline() {
    local -n arr=$1
    local chars=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    local out=""
    for v in "${arr[@]}"; do
        local idx=$(( v * 7 / 100 ))
        (( idx > 7 )) && idx=7
        out+="${chars[$idx]}"
    done
    echo -n "$out"
}

# push value into a history array, capped at HISTORY_LEN
push_history() {
    local -n _arr=$1
    local val=$2
    _arr+=("$val")
    while (( ${#_arr[@]} > HISTORY_LEN )); do
        _arr=("${_arr[@]:1}")
    done
}

# uptime from START_TIME
elapsed() {
    local now=$(date +%s)
    local secs=$(( now - START_TIME ))
    printf '%02d:%02d:%02d' $(( secs/3600 )) $(( (secs%3600)/60 )) $(( secs%60 ))
}

# bytes → human
human_bytes() {
    local kb=$1
    if   (( kb >= 1048576 )); then printf '%.1f GB' "$(echo "$kb/1048576" | bc -l)"
    elif (( kb >= 1024    )); then printf '%.1f MB' "$(echo "$kb/1024"    | bc -l)"
    else                          printf '%d KB'    "$kb"
    fi
}

# ── Metrics ───────────────────────────────────────────────────────────────────

get_cpu() {
    # top snapshot for the PID, grab %CPU column
    local pid=$1
    local pct
    pct=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
    echo "${pct:-0}"
}

get_mem_kb() {
    local pid=$1
    local rss
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    echo "${rss:-0}"
}

get_sys_cpu() {
    # system-wide idle from top (1 sample)
    local idle
    idle=$(top -l 1 -n 0 | awk '/CPU usage/ {
        for(i=1;i<=NF;i++) if ($i ~ /%$/ && $(i-1) ~ /^[0-9.]+$/ && $(i-2) == "idle") print $(i-1)
    }' 2>/dev/null)
    # fallback parse
    if [[ -z "$idle" ]]; then
        idle=$(top -l 1 -n 0 | grep -oE '[0-9.]+% idle' | grep -oE '[0-9.]+')
    fi
    local used
    used=$(echo "100 - ${idle:-50}" | bc 2>/dev/null)
    echo "${used:-0}"
}

get_sys_mem() {
    # physical memory used in KB
    local page_size total free_pages
    page_size=$(pagesize 2>/dev/null || echo 4096)
    total=$(sysctl -n hw.memsize 2>/dev/null)
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
    local free_kb=$(( free_pages * page_size / 1024 ))
    local total_kb=$(( total / 1024 ))
    local used_kb=$(( total_kb - free_kb ))
    local pct=$(( used_kb * 100 / total_kb ))
    echo "$used_kb $total_kb $pct"
}

get_threads() {
    local pid=$1
    # ps doesn't give thread count cleanly; use lsof or proc
    local t
    t=$(ps -M -p "$pid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    echo "${t:-?}"
}

get_fds() {
    local pid=$1
    local n
    n=$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')
    echo "${n:-?}"
}

get_disk_rw() {
    # iotop not available on macOS without sudo; use fs_usage briefly
    # Just read from /proc equivalent – skip gracefully
    echo "N/A"
}

# ── Layout ────────────────────────────────────────────────────────────────────
COLS=80
ROWS=30

draw_header() {
    local pid=$1
    move 1 1
    printf '%s%s%s' "$BG_HEADER" "$FG_TITLE$BOLD"
    printf '  ⚙  ComfyPilot Monitor'
    printf '%s' "$FG_LABEL"
    printf '   PID: %s%s%s' "$FG_CYAN$BOLD" "$pid" "$FG_LABEL"
    printf '   Uptime: %s%s' "$FG_WHITE" "$(elapsed)"
    printf '   %s%s' "$FG_LABEL" "$(date '+%H:%M:%S')"
    printf '%s\n' "$R"
    printf '%s%s\n%s' "$FG_DIM" "$(printf '─%.0s' $(seq 1 $COLS))" "$R"
}

draw_section_title() {
    local row=$1 col=$2 title=$3
    move "$row" "$col"
    printf '%s %s %s' "$FG_CYAN$BOLD" "$title" "$R"
}

draw_process_panel() {
    local row=$1 pid=$2 cpu=$3 mem_kb=$4 threads=$5 fds=$6
    local mem_mb
    mem_mb=$(echo "$mem_kb / 1024" | bc 2>/dev/null)

    draw_section_title "$row" 2 "● PROCESS"
    (( row++ ))

    move "$row" 3
    printf '%sCPU    %s' "$FG_LABEL" "$R"
    local cpu_int="${cpu%.*}"
    (( cpu_int > 100 )) && cpu_int=100
    printf '%s%5.1f%%%s  ' "$(pct_color $cpu_int)" "$cpu" "$R"
    bar "$cpu_int" 24
    (( row++ ))

    move "$row" 3
    printf '%sMEM    %s' "$FG_LABEL" "$R"
    printf '%s%s%s (%s KB)' "$FG_VALUE" "$(human_bytes $mem_kb)" "$R" "$FG_DIM$mem_kb$R"
    (( row++ ))

    move "$row" 3
    printf '%sThreads%s  %s%s%s' "$FG_LABEL" "$R" "$FG_VALUE" "$threads" "$R"
    printf '     %sFDs%s  %s%s%s' "$FG_LABEL" "$R" "$FG_VALUE" "$fds" "$R"
}

draw_system_panel() {
    local row=$1 sys_cpu=$2 mem_used=$3 mem_total=$4 mem_pct=$5
    local sys_cpu_int="${sys_cpu%.*}"
    (( sys_cpu_int > 100 )) && sys_cpu_int=100

    draw_section_title "$row" 2 "◈ SYSTEM"
    (( row++ ))

    move "$row" 3
    printf '%sCPU    %s' "$FG_LABEL" "$R"
    printf '%s%5.1f%%%s  ' "$(pct_color $sys_cpu_int)" "$sys_cpu" "$R"
    bar "$sys_cpu_int" 24
    (( row++ ))

    move "$row" 3
    printf '%sMEM    %s' "$FG_LABEL" "$R"
    printf '%s%5d%%%s  ' "$(pct_color $mem_pct)" "$mem_pct" "$R"
    bar "$mem_pct" 24
    printf '  %s%s / %s%s' "$FG_VALUE" "$(human_bytes $mem_used)" "$(human_bytes $mem_total)" "$R"
}

draw_sparklines() {
    local row=$1
    draw_section_title "$row" 2 "▲ HISTORY  (last ${HISTORY_LEN}s)"
    (( row++ ))

    move "$row" 3
    printf '%sProc CPU  %s' "$FG_LABEL" "$R"
    printf '%s' "$FG_GREEN"
    sparkline cpu_history
    printf '%s\n' "$R"
    (( row++ ))

    move "$row" 3
    printf '%sProc MEM  %s' "$FG_LABEL" "$R"
    printf '%s' "$FG_CYAN"
    sparkline mem_history
    printf '%s' "$R"
}

draw_log_panel() {
    local row=$1
    draw_section_title "$row" 2 "≡ LIVE LOG  (stdout/stderr)"
}

draw_footer() {
    local row=$1
    move "$row" 1
    printf '%s%s%s' "$FG_DIM" "$(printf '─%.0s' $(seq 1 $COLS))" "$R"
    (( row++ ))
    move "$row" 2
    printf '%s[q]%s quit   %s[r]%s restart   %s[k]%s kill app   %s[c]%s clear log%s' \
        "$FG_CYAN$BOLD" "$FG_LABEL" \
        "$FG_CYAN$BOLD" "$FG_LABEL" \
        "$FG_RED$BOLD"  "$FG_LABEL" \
        "$FG_YELLOW$BOLD" "$FG_LABEL" "$R"
}

# ── Log buffer ────────────────────────────────────────────────────────────────
LOG_LINES=()
MAX_LOG=8
LOG_ROW=23

append_log() {
    local line="$1"
    # strip ANSI for length check but keep for display
    LOG_LINES+=("$line")
    while (( ${#LOG_LINES[@]} > MAX_LOG )); do
        LOG_LINES=("${LOG_LINES[@]:1}")
    done
}

redraw_log() {
    local start_row=$LOG_ROW
    local i
    for (( i=0; i<MAX_LOG; i++ )); do
        move $(( start_row + i )) 3
        # clear line
        printf '\e[2K'
        if [[ -n "${LOG_LINES[$i]}" ]]; then
            printf '%s%s%s' "$FG_DIM" "${LOG_LINES[$i]:0:75}" "$R"
        fi
    done
}

# ── Build & Launch ────────────────────────────────────────────────────────────

do_build() {
    clear_screen
    printf '%sBUILDING %s%s…%s\n' "$FG_ORANGE$BOLD" "$FG_WHITE" "$SCHEME" "$R"
    printf '%s%s%s\n' "$FG_DIM" "$(printf '─%.0s' $(seq 1 $COLS))" "$R"

    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED" \
        build 2>&1 | while IFS= read -r line; do
            # color xcodebuild output
            if [[ "$line" == *error:* ]];   then printf '%s%s%s\n' "$FG_RED"    "$line" "$R"
            elif [[ "$line" == *warning:* ]]; then printf '%s%s%s\n' "$FG_YELLOW" "$line" "$R"
            elif [[ "$line" == BUILD\ SUCCEEDED* ]] || [[ "$line" == *"** BUILD SUCCEEDED **"* ]]; then
                printf '%s%s%s\n' "$FG_GREEN$BOLD" "$line" "$R"
            else printf '%s%s%s\n' "$FG_DIM" "$line" "$R"
            fi
        done

    if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
        printf '\n%s❌  Build failed. Fix errors above.%s\n' "$FG_RED$BOLD" "$R"
        show_cursor; exit 1
    fi
    printf '\n%s✅  Build succeeded!%s\n' "$FG_GREEN$BOLD" "$R"
    sleep 1
}

launch_app() {
    if [[ ! -x "$EXEC" ]]; then
        printf '%s❌ Executable not found: %s%s\n' "$FG_RED" "$EXEC" "$R"
        show_cursor; exit 1
    fi

    # launch app, redirect output to a temp fifo
    LOG_FIFO=$(mktemp -t comfy_log)
    rm -f "$LOG_FIFO"; mkfifo "$LOG_FIFO"

    "$EXEC" >"$LOG_FIFO" 2>&1 &
    APP_PID=$!

    # background reader into LOG_LINES
    while IFS= read -r line; do
        append_log "$line"
    done < "$LOG_FIFO" &
    LOG_READER_PID=$!
}

# ── Main TUI Loop ─────────────────────────────────────────────────────────────

cleanup() {
    show_cursor
    tput rmcup 2>/dev/null || true
    [[ -n "$LOG_READER_PID" ]] && kill "$LOG_READER_PID" 2>/dev/null || true
    [[ -n "$LOG_FIFO" ]]      && rm -f "$LOG_FIFO"
    printf '\n%sComfyPilot Monitor exited.%s\n' "$FG_LABEL" "$R"
}
trap cleanup EXIT INT TERM

# ── Entry Point ───────────────────────────────────────────────────────────────

# If PID passed as arg, attach to existing process
if [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; then
    APP_PID="$1"
    printf '%sAttaching to PID %s…%s\n' "$FG_CYAN" "$APP_PID" "$R"
    sleep 0.5
else
    do_build
    launch_app
fi

tput smcup 2>/dev/null || true
hide_cursor
clear_screen

# ── Draw loop ─────────────────────────────────────────────────────────────────

declare -i tick=0

while true; do
    # Check if process is still alive
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        move 15 2
        printf '%s⚠  Process (PID %s) has exited.  Press [r] to restart or [q] to quit.%s' \
            "$FG_YELLOW$BOLD" "$APP_PID" "$R"
        APP_PID=""
    fi

    # ── Gather metrics (skip heavy ones if no PID) ──
    if [[ -n "$APP_PID" ]]; then
        cpu=$(get_cpu "$APP_PID")
        mem_kb=$(get_mem_kb "$APP_PID")
        threads=$(get_threads "$APP_PID")
        fds=$(get_fds "$APP_PID")

        cpu_pct_int="${cpu%.*}"; (( cpu_pct_int > 100 )) && cpu_pct_int=100
        mem_pct_raw=$(( mem_kb / 1024 ))   # store MB for sparkline (0-1000 → clamp to 100)
        mem_spark=$(( mem_pct_raw > 100 ? 100 : mem_pct_raw ))

        push_history cpu_history "$cpu_pct_int"
        push_history mem_history "$mem_spark"
    fi

    # system metrics every 2 ticks to reduce load
    if (( tick % 2 == 0 )); then
        read -r sys_cpu_raw <<< "$(get_sys_cpu)"
        read -r mem_used mem_total mem_pct <<< "$(get_sys_mem)"
    fi

    # ── Redraw ──────────────────────────────────────────────────────────────
    draw_header "${APP_PID:-dead}"

    if [[ -n "$APP_PID" ]]; then
        draw_process_panel 3 "$APP_PID" "$cpu" "$mem_kb" "$threads" "$fds"
    fi

    move 9 1; printf '%s%s%s' "$FG_DIM" "$(printf '·%.0s' $(seq 1 $COLS))" "$R"
    draw_system_panel 10 "${sys_cpu_raw:-0}" "${mem_used:-0}" "${mem_total:-1}" "${mem_pct:-0}"

    move 14 1; printf '%s%s%s' "$FG_DIM" "$(printf '·%.0s' $(seq 1 $COLS))" "$R"
    draw_sparklines 15

    move 19 1; printf '%s%s%s' "$FG_DIM" "$(printf '·%.0s' $(seq 1 $COLS))" "$R"
    draw_log_panel 20

    redraw_log

    draw_footer 32

    # ── Non-blocking key read ──────────────────────────────────────────────
    IFS= read -r -s -n1 -t "$REFRESH" key 2>/dev/null || true
    case "$key" in
        q|Q) exit 0 ;;
        k|K)
            if [[ -n "$APP_PID" ]]; then
                kill "$APP_PID" 2>/dev/null
                append_log "$(date '+%H:%M:%S') [monitor] Killed PID $APP_PID"
                APP_PID=""
            fi ;;
        r|R)
            clear_screen
            tput rmcup 2>/dev/null || true
            show_cursor
            do_build
            launch_app
            START_TIME=$(date +%s)
            cpu_history=(); mem_history=()
            tput smcup 2>/dev/null || true
            hide_cursor
            clear_screen ;;
        c|C) LOG_LINES=() ;;
    esac

    (( tick++ )) || true
done
