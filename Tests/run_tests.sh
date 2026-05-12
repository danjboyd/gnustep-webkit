#!/bin/bash
#
# Automated WebKitDemo tests under Xvfb.
#
# Each test launches the demo with WKDEMO_TEST_MODE=1, drives it via
# stdin (GOTO / EVAL / RESIZE / QUIT), reads results from a log file,
# and asserts.  Mouse events are synthesised with xdotool.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

XDISP=":99"
TMP=$(mktemp -d /tmp/wkdemo-tests.XXXXXX)

PASS=0
FAIL=0

TEST_PID=0
TEST_LOG=""
TEST_FIFO=""

cleanup() {
  if [ "$TEST_PID" -ne 0 ]; then
    kill -9 "$TEST_PID" 2>/dev/null
  fi
  exec 9>&- 2>/dev/null
  pkill -9 WebKitDemo 2>/dev/null
  pkill -9 WPEWebProcess 2>/dev/null
  pkill -9 WebKitNetworkProcess 2>/dev/null
  pkill -9 -f "Xvfb $XDISP" 2>/dev/null
  if [ -n "${WKDEMO_KEEP_LOGS:-}" ]; then
    echo "logs preserved at $TMP"
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT


# ---------- Xvfb -----------------------------------------------------

start_xvfb() {
  pkill -9 -f "Xvfb $XDISP" 2>/dev/null
  pkill -9 -f "gpbs" 2>/dev/null
  sleep 0.3
  Xvfb $XDISP -screen 0 1280x900x24 >/dev/null 2>&1 &
  local i=0
  while ! xdpyinfo -display $XDISP >/dev/null 2>&1; do
    sleep 0.1
    i=$((i+1))
    if [ $i -gt 50 ]; then echo "Xvfb didn't start"; exit 1; fi
  done
  # gpbs (GNUstep Pasteboard Server) must be running for NSPasteboard
  # to work.  Start it bound to our Xvfb display.
  DISPLAY=$XDISP gpbs >/dev/null 2>&1 &
  sleep 0.5
}


# ---------- Demo process lifecycle ----------------------------------

setup_demo() {
  local tag="$1"
  TEST_LOG="$TMP/$tag.log"
  TEST_FIFO="$TMP/$tag.in"
  : > "$TEST_LOG"
  rm -f "$TEST_FIFO"
  mkfifo "$TEST_FIFO"

  # Keep the fifo writer side open in this shell so the demo doesn't
  # see EOF on stdin until we close fd 9.  Use rw mode (<>) so opening
  # does not block waiting for a reader.
  exec 9<>"$TEST_FIFO"

  LD_LIBRARY_PATH="$REPO/Source/obj:${LD_LIBRARY_PATH:-}" \
  DISPLAY=$XDISP \
  WKDEMO_TEST_MODE=1 \
  WKDEMO_TRACE_EVENTS="${WKDEMO_TRACE_EVENTS:-0}" \
  WEBKIT_DEBUG="${WEBKIT_DEBUG:-}" \
    "$REPO/Demo/WebKitDemo.app/WebKitDemo" <"$TEST_FIFO" 2>"$TEST_LOG" &
  TEST_PID=$!

  if ! wait_for "WKDEMO_READY" 10; then
    echo "  demo did not become ready (log tail follows):"
    tail -n 30 "$TEST_LOG" | sed 's/^/    /'
    teardown_demo
    return 1
  fi
  return 0
}

teardown_demo() {
  if [ "$TEST_PID" -ne 0 ]; then
    send_cmd "QUIT"
    # Give the app a moment to terminate normally, then escalate.
    local i=0
    while kill -0 "$TEST_PID" 2>/dev/null && [ $i -lt 20 ]; do
      sleep 0.1
      i=$((i+1))
    done
    kill -9 "$TEST_PID" 2>/dev/null
    wait "$TEST_PID" 2>/dev/null
  fi
  exec 9>&- 2>/dev/null
  TEST_PID=0
  pkill -9 WPEWebProcess 2>/dev/null
  pkill -9 WebKitNetworkProcess 2>/dev/null
}

send_cmd() {
  echo "$*" >&9
}

wait_for() {
  local pattern="$1" timeout="${2:-10}"
  local end=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if grep -qE "$pattern" "$TEST_LOG" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# Send EVAL and return its result string with the prefix stripped.
# Uses a marker so it's safe to call repeatedly.
count_eval_results() {
  # awk always prints one integer, including 0 on no matches.  grep -c
  # is unreliable here because it exits 1 on no matches and the
  # || echo 0 fallback then duplicates output.
  awk '/^WKDEMO_EVAL_RESULT:/{n++} END{print n+0}' "$TEST_LOG" 2>/dev/null
}

eval_js() {
  local before count
  before=$(count_eval_results)
  send_cmd "EVAL $*"
  local i=0
  while [ $i -lt 100 ]; do
    count=$(count_eval_results)
    if [ "$count" -gt "$before" ]; then
      grep '^WKDEMO_EVAL_RESULT:' "$TEST_LOG" | tail -n 1 | sed 's/^WKDEMO_EVAL_RESULT: //'
      return 0
    fi
    sleep 0.1
    i=$((i+1))
  done
  echo "TIMEOUT"
  return 1
}


# ---------- assertions ----------------------------------------------

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name"
    echo "    got:  [$got]"
    echo "    want: [$want]"
    FAIL=$((FAIL+1))
  fi
}

assert_match() {
  local name="$1" got="$2" pattern="$3"
  if echo "$got" | grep -qE "$pattern"; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name"
    echo "    got:     [$got]"
    echo "    pattern: [$pattern]"
    FAIL=$((FAIL+1))
  fi
}


# ---------- shared test fixture --------------------------------------

TEST_HTML='<!doctype html><html><head><style>
body{margin:0;font-family:sans-serif;color:#000;background:#fff;font-size:24px}
#para{position:absolute;left:50px;top:80px;width:600px;line-height:1.4;background:#ffff80;padding:8px;user-select:text;-webkit-user-select:text}
</style><script>
window._evt={down:0,up:0,move:0,click:0,sel:0,lastMove:"",lastDown:"",moveTargets:[],sels:[],defaultsPrevented:0};
function tgt(e){return e.target?(e.target.tagName||"")+"#"+(e.target.id||""):"-"}
window.addEventListener("mousedown",function(e){window._evt.down++;window._evt.lastDown=e.clientX+","+e.clientY+"/btn="+e.button+"/btns="+e.buttons+"/tgt="+tgt(e);},true);
window.addEventListener("mouseup",function(e){window._evt.up++;},true);
window.addEventListener("mousemove",function(e){window._evt.move++;window._evt.lastMove=e.clientX+","+e.clientY+"/btns="+e.buttons+"/tgt="+tgt(e);if(window._evt.moveTargets.length<5)window._evt.moveTargets.push(tgt(e));},true);
window.addEventListener("click",function(e){window._evt.click++;},true);
document.addEventListener("selectionchange",function(e){window._evt.sel++;var s=window.getSelection();window._evt.sels.push("a"+s.anchorOffset+"f"+s.focusOffset);});
window.addEventListener("dragstart",function(e){window._evt.dragstart=true;},true);
window.addEventListener("drag",function(e){window._evt.drag=(window._evt.drag||0)+1;},true);
</script></head><body>
<p id="para">The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. Sphinx of black quartz judge my vow.</p>
</body></html>'

encode() { python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }
TEST_DATA_URL="data:text/html;charset=utf-8,$(encode "$TEST_HTML")"


# =====================================================================
test_load() {
  echo "[test_load]"
  setup_demo load || return

  send_cmd "GOTO $TEST_DATA_URL"
  if ! wait_for "WKDEMO_LOADED:" 15; then
    echo "  page never loaded"; FAIL=$((FAIL+1)); teardown_demo; return
  fi

  assert_match "innerText length positive" \
    "$(eval_js "document.getElementById('para').innerText.length")" \
    '^number [1-9][0-9]*$'

  teardown_demo
}

# =====================================================================
test_drag_select() {
  echo "[test_drag_select]"
  setup_demo drag || return

  send_cmd "GOTO $TEST_DATA_URL"
  if ! wait_for "WKDEMO_LOADED:" 15; then
    echo "  page never loaded"; FAIL=$((FAIL+1)); teardown_demo; return
  fi
  sleep 1

  # Sanity: which element does the page think is at our drag origin?
  echo "  innerWidth = $(eval_js "window.innerWidth")"
  echo "  paragraph at (60,120): $(eval_js "var e = document.elementFromPoint(60,120); e ? e.tagName + '#' + (e.id||'') : 'null'")"

  # First test: programmatic selection.  If this works, WebKit's
  # selection rendering is fine and any failure later is in event
  # dispatch.
  eval_js "var r=document.createRange();r.selectNodeContents(document.getElementById('para'));var s=window.getSelection();s.removeAllRanges();s.addRange(r);" >/dev/null
  assert_match "programmatic selection has text" \
    "$(eval_js "window.getSelection().toString().length")" \
    '^number [1-9][0-9]*$'
  eval_js "window.getSelection().removeAllRanges();" >/dev/null
  assert_eq "selection cleared" "$(eval_js "window.getSelection().toString().length")" "number 0"

  # Compute screen-space coordinates of mid-second-line text using JS,
  # so we don't rely on toolkit decoration sizes.
  local rect_top rect_left
  rect_top=$(eval_js "document.getElementById('para').getBoundingClientRect().top")
  rect_left=$(eval_js "document.getElementById('para').getBoundingClientRect().left")
  echo "  para rect: left=$rect_left top=$rect_top"

  # Where is the demo window on the X screen?
  local wid x y
  wid=$(DISPLAY=$XDISP xdotool search --name "GNUstep WebKit Demo" | head -n 1)
  if [ -z "$wid" ]; then echo "  no window"; FAIL=$((FAIL+1)); teardown_demo; return; fi
  DISPLAY=$XDISP xdotool windowmove "$wid" 0 0 2>/dev/null
  sleep 0.3

  # Position of the WKWebView origin in window coords.  In the demo we
  # build the layout manually: top toolbar row at y=cb.h-36 (height
  # 26), js row 32px below, then web view fills the remaining height
  # above an 8+~28px status row.  Net top inset from window top is
  # 8 (window chrome) + 28 (title) + (toolbar 26 + gap 6) + (js 24 +
  # gap 8).  Hard to know without inspecting; instead use xdotool to
  # find the window's exact geometry on screen, then add a generous
  # vertical offset to land somewhere in the page text region.
  local geom
  geom=$(DISPLAY=$XDISP xdotool getwindowgeometry --shell "$wid" 2>/dev/null)
  local WX WY
  WX=$(echo "$geom" | awk -F= '/^X=/{print $2}')
  WY=$(echo "$geom" | awk -F= '/^Y=/{print $2}')
  echo "  window pos: $WX, $WY"

  # Approximate; the web view top is offset by the AppKit chrome.  In
  # our demo the chrome above the web view is about 28 (title) + 36
  # (toolbar) + 32 (js row) = 96px from the window's outer top.  Then
  # the paragraph sits 80px down inside the web view.
  local CHROME_TOP=96
  # Aim well inside the text: ~150px right of paragraph left edge
  local x_start=$(( WX + 8 + 50 + 150 ))
  local x_end=$(( x_start + 250 ))
  local y_pos=$(( WY + CHROME_TOP + 100 ))

  echo "  drag from ${x_start},${y_pos} -> ${x_end},${y_pos}"

  # Try shift+click sequence: focus + position then shift+click far to
  # the right should extend selection if the basic selection logic is
  # working in WebKit at all.
  DISPLAY=$XDISP xdotool mousemove --sync "$x_start" "$y_pos"
  DISPLAY=$XDISP xdotool click 1
  sleep 0.3
  echo "  before shift-click: anchor=$(eval_js "window.getSelection().anchorOffset") focus=$(eval_js "window.getSelection().focusOffset")"
  DISPLAY=$XDISP xdotool mousemove --sync "$x_end" "$y_pos"
  DISPLAY=$XDISP xdotool keydown shift
  DISPLAY=$XDISP xdotool click 1
  DISPLAY=$XDISP xdotool keyup shift
  sleep 0.5
  echo "  after shift-click: anchor=$(eval_js "window.getSelection().anchorOffset") focus=$(eval_js "window.getSelection().focusOffset")"
  echo "  shift-selection: $(eval_js "window.getSelection().toString()")"

  # Now the plain drag.
  eval_js "window.getSelection().removeAllRanges();window._evt={down:0,up:0,move:0,click:0,sel:0,lastMove:'',lastDown:''};" >/dev/null
  DISPLAY=$XDISP xdotool mousemove --sync "$x_start" "$y_pos"
  DISPLAY=$XDISP xdotool mousedown 1
  sleep 0.2
  for step in $(seq 1 12); do
    local xi=$(( x_start + (x_end - x_start) * step / 12 ))
    DISPLAY=$XDISP xdotool mousemove --sync "$xi" "$y_pos"
    sleep 0.05
  done
  sleep 0.3
  echo "  during drag (before mouseup): $(eval_js "JSON.stringify(window._evt)")"
  echo "  anchor=$(eval_js "window.getSelection().anchorOffset")  focus=$(eval_js "window.getSelection().focusOffset")"
  DISPLAY=$XDISP xdotool mouseup 1
  sleep 0.6

  local sel_text sel_len
  sel_text=$(eval_js "window.getSelection().toString()")
  sel_len=$(eval_js "window.getSelection().toString().length")
  echo "  selection: [$sel_text]"
  echo "  length:    [$sel_len]"
  echo "  anchor=$(eval_js "window.getSelection().anchorOffset")  focus=$(eval_js "window.getSelection().focusOffset")"
  echo "  events seen: $(eval_js "JSON.stringify(window._evt)")"

  assert_match "selection length > 0" "$sel_len" '^number [1-9][0-9]*$'

  teardown_demo
}

# =====================================================================
test_resize_repaint() {
  echo "[test_resize_repaint]"
  setup_demo resize || return

  send_cmd "GOTO $TEST_DATA_URL"
  if ! wait_for "WKDEMO_LOADED:" 15; then
    echo "  page never loaded"; FAIL=$((FAIL+1)); teardown_demo; return
  fi
  sleep 1

  local w0 w1 w2
  w0=$(eval_js "window.innerWidth")
  send_cmd "RESIZE 800 600"
  sleep 1
  w1=$(eval_js "window.innerWidth")
  send_cmd "RESIZE 1200 800"
  sleep 1
  w2=$(eval_js "window.innerWidth")

  echo "  initial=$w0  after 800x600=$w1  after 1200x800=$w2"
  assert_match "innerWidth shrinks on RESIZE 800" "$w1" '^number ([1-7][0-9]{0,2}|800)$'
  assert_match "innerWidth grows on RESIZE 1200" "$w2" '^number (1[01][0-9]{2}|1200)$'

  teardown_demo
}


# =====================================================================
test_paste() {
  echo "[test_paste]"
  setup_demo paste || return

  # Two inputs: src has the secret to copy, dst is where paste goes.
  PASTE_HTML='<!doctype html><html><body>
<input id="src" value="hunter2-secret-123" style="width:400px;font-size:24px">
<br>
<input id="dst" style="width:400px;font-size:24px">
</body></html>'
  PASTE_URL="data:text/html;charset=utf-8,$(encode "$PASTE_HTML")"
  send_cmd "GOTO $PASTE_URL"
  if ! wait_for "WKDEMO_LOADED:" 15; then
    echo "  page never loaded"; FAIL=$((FAIL+1)); teardown_demo; return
  fi
  sleep 0.5

  local wid
  wid=$(DISPLAY=$XDISP xdotool search --name "GNUstep WebKit Demo" | head -n 1)
  DISPLAY=$XDISP xdotool windowmove "$wid" 0 0 2>/dev/null
  sleep 0.2

  # WKWebView needs to be the window's first responder before keyboard
  # events route to it.  A click anywhere in the web view does that.
  DISPLAY=$XDISP xdotool mousemove --sync 100 250
  DISPLAY=$XDISP xdotool click 1
  sleep 0.3

  # ---- Round-trip via NSPasteboard (framework's own copy/paste path).
  # Select all of src and Ctrl+C.
  eval_js "document.getElementById('src').focus();document.getElementById('src').select();" >/dev/null
  sleep 0.2
  DISPLAY=$XDISP xdotool key --clearmodifiers ctrl+c
  sleep 0.5

  # Focus dst and Ctrl+V.
  eval_js "document.getElementById('dst').focus();" >/dev/null
  sleep 0.2
  DISPLAY=$XDISP xdotool key --clearmodifiers ctrl+v
  sleep 0.6

  echo "  src after copy: $(eval_js "document.getElementById('src').value")"
  echo "  dst after paste: $(eval_js "document.getElementById('dst').value")"
  assert_match "dst contains pasted text" \
    "$(eval_js "document.getElementById('dst').value")" \
    "string hunter2-secret-123"

  teardown_demo
}


# ---------- driver --------------------------------------------------

TESTS="${1:-load drag_select resize_repaint paste}"
start_xvfb

for t in $TESTS; do
  test_$t
done

echo
echo "==== $PASS passed, $FAIL failed ===="
[ $FAIL -eq 0 ]
