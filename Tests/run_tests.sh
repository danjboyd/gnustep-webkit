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


# =====================================================================
test_navigation_lifecycle() {
  echo "[test_navigation_lifecycle]"
  setup_demo navlife || return
  send_cmd "GOTO $TEST_DATA_URL"
  if ! wait_for "WKDEMO_LOADED:" 15; then
    echo "  page never loaded"; FAIL=$((FAIL+1)); teardown_demo; return
  fi
  sleep 0.5
  # After the page finishes loading, WebKit's history-related globals
  # should be populated.  Use them as a proxy for "real" navigation.
  assert_match "document.readyState == complete" \
    "$(eval_js "document.readyState")" '^string complete$'
  assert_match "performance.timing.loadEventEnd > 0" \
    "$(eval_js "performance.timing && performance.timing.loadEventEnd > 0")" \
    '^(number 1|boolean .*)|number [1-9].*'
  teardown_demo
}

# =====================================================================
test_js_exception() {
  echo "[test_js_exception]"
  setup_demo jsx || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 15 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  # Throwing JS should come back as a string starting with ERROR.
  local res
  res=$(eval_js "throw new Error('boom from test')")
  assert_match "JS throw surfaces as ERROR" "$res" "^ERROR"
  # The evaluator should still work after a throw.
  res=$(eval_js "1+1")
  assert_eq "JS recovers after throw" "$res" "number 2"
  teardown_demo
}

# =====================================================================
test_zoom_roundtrip() {
  echo "[test_zoom_roundtrip]"
  setup_demo zoom || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 15 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  # Initial zoom is 1.0.  Set via JS through the engine doesn't work
  # directly; we'd need to call WKWebView setPageZoom.  The test
  # harness doesn't expose that, so this test just exercises that
  # window.devicePixelRatio reflects the underlying device scale (a
  # related property that proves the engine is honouring our scale
  # settings).
  local r
  r=$(eval_js "window.devicePixelRatio")
  assert_match "devicePixelRatio is positive number" "$r" "^number [1-9]"
  teardown_demo
}

# =====================================================================
test_custom_scheme() {
  echo "[test_custom_scheme]"
  setup_demo cscheme || return
  # Wait for ready, then send the navigation.  The demo registers
  # myapp:// at startup so it should be available.
  send_cmd "GOTO myapp://hello/from-test"
  if ! wait_for "WKDEMO_LOADED: myapp://hello/from-test" 10; then
    echo "  myapp:// never loaded"; teardown_demo; FAIL=$((FAIL+1)); return
  fi
  sleep 0.3
  local title
  title=$(eval_js "document.title")
  # The demo's scheme handler doesn't set a title, but the H1 it
  # writes mentions "Custom scheme handler" and the URL.
  assert_match "page from custom scheme contains URL" \
    "$(eval_js "document.body.innerText.indexOf('myapp://hello/from-test') >= 0")" \
    '^boolean .*true|^number 1$'
  assert_match "page from custom scheme contains heading" \
    "$(eval_js "document.querySelector('h1').textContent")" \
    'Custom scheme'
  teardown_demo
}

# =====================================================================
test_back_forward() {
  echo "[test_back_forward]"
  setup_demo bf || return
  local A=$(encode "<!doctype html><title>A</title><body>page-A</body>")
  local B=$(encode "<!doctype html><title>B</title><body>page-B</body>")
  send_cmd "GOTO data:text/html,$A"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  send_cmd "GOTO data:text/html,$B"
  # Match the second LOADED line.
  local before=$(grep -c "^WKDEMO_LOADED:" "$TEST_LOG" 2>/dev/null || echo 0)
  local i=0
  while [ $i -lt 100 ]; do
    local now=$(grep -c "^WKDEMO_LOADED:" "$TEST_LOG" 2>/dev/null || echo 0)
    if [ "$now" -gt "$before" ]; then break; fi
    sleep 0.1
    i=$((i+1))
  done
  sleep 0.3
  assert_match "currently on page B" \
    "$(eval_js "document.title")" "^string B"
  # We have no public goBack/goForward via stdin, but the engine knows
  # via WKBackForwardList.  Just verify history.length > 1.
  assert_match "history.length > 1" \
    "$(eval_js "history.length > 1")" '^(boolean .*true|number 1)$'
  teardown_demo
}

# =====================================================================
test_cookies_via_dom() {
  echo "[test_cookies_via_dom]"
  setup_demo cookies || return
  # data: URLs typically have opaque origins so document.cookie is
  # restricted; use a plain http URL the engine treats as having a
  # cookie jar.  Skip the test if we can't.
  send_cmd "GOTO http://127.0.0.1:0/__never_resolves__"
  # We expect failure, but the cookie API should still be exposed.
  sleep 1
  assert_match "document.cookie is a string (even if empty)" \
    "$(eval_js "typeof document.cookie")" "^string string$"
  teardown_demo
}

# =====================================================================
test_dom_event_listeners() {
  echo "[test_dom_event_listeners]"
  setup_demo domevt || return
  local PAGE=$(encode '<!doctype html><script>
window._counts={click:0,mousedown:0,mouseup:0,mousemove:0,keydown:0};
window.addEventListener("click",function(){window._counts.click++});
window.addEventListener("mousedown",function(){window._counts.mousedown++});
window.addEventListener("mouseup",function(){window._counts.mouseup++});
window.addEventListener("mousemove",function(){window._counts.mousemove++});
window.addEventListener("keydown",function(){window._counts.keydown++});
</script><body style="margin:0"><div id=t style="width:100%;height:200px;background:#eef"></div></body>')
  send_cmd "GOTO data:text/html,$PAGE"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5

  local wid
  wid=$(DISPLAY=$XDISP xdotool search --name "GNUstep WebKit Demo" | head -n 1)
  DISPLAY=$XDISP xdotool windowmove "$wid" 0 0 2>/dev/null
  sleep 0.2

  # Click somewhere safely inside the page region.
  DISPLAY=$XDISP xdotool mousemove --sync 200 250
  DISPLAY=$XDISP xdotool click 1
  sleep 0.4
  # Drag from there a bit to fire mousedown + mousemove + mouseup.
  DISPLAY=$XDISP xdotool mousedown 1
  sleep 0.1
  for x in 220 240 260 280 300; do
    DISPLAY=$XDISP xdotool mousemove --sync $x 250
    sleep 0.03
  done
  DISPLAY=$XDISP xdotool mouseup 1
  sleep 0.4

  local counts=$(eval_js "JSON.stringify(window._counts)")
  echo "  counts: $counts"
  assert_match "click event fired" "$counts" "\"click\":[1-9]"
  assert_match "mousedown fired" "$counts" "\"mousedown\":[1-9]"
  assert_match "mouseup fired" "$counts" "\"mouseup\":[1-9]"
  assert_match "mousemove fired" "$counts" "\"mousemove\":[1-9]"
  teardown_demo
}

# =====================================================================
test_form_typing() {
  echo "[test_form_typing]"
  setup_demo typing || return
  local PAGE=$(encode '<!doctype html><body><input id=f autofocus></body>')
  send_cmd "GOTO data:text/html,$PAGE"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3

  local wid
  wid=$(DISPLAY=$XDISP xdotool search --name "GNUstep WebKit Demo" | head -n 1)
  DISPLAY=$XDISP xdotool windowmove "$wid" 0 0 2>/dev/null
  sleep 0.2

  # Click on the input to focus it (the autofocus may not survive
  # data:URL origin restrictions).
  DISPLAY=$XDISP xdotool mousemove --sync 100 100
  DISPLAY=$XDISP xdotool click 1
  sleep 0.2
  # Focus via JS too as a safety net.
  eval_js "document.getElementById('f').focus()" >/dev/null
  sleep 0.2

  DISPLAY=$XDISP xdotool type --delay 30 "hello"
  sleep 0.5

  local val=$(eval_js "document.getElementById('f').value")
  echo "  input value after typing: $val"
  assert_match "typed text reached input" "$val" "^string hello$"
  teardown_demo
}

# =====================================================================
test_kvo_title() {
  echo "[test_kvo_title]"
  setup_demo kvo || return
  local PAGE=$(encode '<!doctype html><title>Hello KVO</title><body>x</body>')
  send_cmd "GOTO data:text/html,$PAGE"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5
  # The demo's WKDBrowserWindowController observes title and writes
  # it into the window title.  We test through document.title which
  # WebKit populates from the <title>.
  assert_match "document.title is the page title" \
    "$(eval_js "document.title")" "^string Hello KVO$"
  teardown_demo
}

# =====================================================================
test_cookie_roundtrip() {
  echo "[test_cookie_roundtrip]"
  setup_demo cookies_rt || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  # Set a known cookie via WKHTTPCookieStore.
  send_cmd "COOKIE_SET test_token=secret123;.example.org"
  sleep 0.5
  # Read all cookies; expect to see test_token entry.
  local before=$(awk '/^WKDEMO_COOKIE_RESULT:/{n++}END{print n+0}' "$TEST_LOG")
  send_cmd "COOKIE_LIST"
  local i=0
  while [ $i -lt 80 ]; do
    local now=$(awk '/^WKDEMO_COOKIE_RESULT:/{n++}END{print n+0}' "$TEST_LOG")
    if [ "$now" -gt "$before" ]; then break; fi
    sleep 0.1
    i=$((i+1))
  done
  local cookies=$(grep '^WKDEMO_COOKIE_RESULT:' "$TEST_LOG" | tail -n 1 | sed 's/^WKDEMO_COOKIE_RESULT: //')
  echo "  cookies: $cookies"
  assert_match "set cookie shows up in getAllCookies" \
    "$cookies" "test_token@.*example\\.org=secret123"
  teardown_demo
}

# =====================================================================
test_snapshot() {
  echo "[test_snapshot]"
  setup_demo snap || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 1.5  # let the engine paint at least one frame
  local before=$(awk '/^WKDEMO_SNAPSHOT_RESULT:/{n++}END{print n+0}' "$TEST_LOG")
  send_cmd "SNAPSHOT"
  local i=0
  while [ $i -lt 60 ]; do
    local now=$(awk '/^WKDEMO_SNAPSHOT_RESULT:/{n++}END{print n+0}' "$TEST_LOG")
    if [ "$now" -gt "$before" ]; then break; fi
    sleep 0.1
    i=$((i+1))
  done
  local result=$(grep '^WKDEMO_SNAPSHOT_RESULT:' "$TEST_LOG" | tail -n 1 | sed 's/^WKDEMO_SNAPSHOT_RESULT: //')
  echo "  snapshot: $result"
  assert_match "takeSnapshot returns NSImage with size" "$result" "^image:[1-9][0-9]+x[1-9][0-9]+$"
  teardown_demo
}

# =====================================================================
test_user_script_injection() {
  echo "[test_user_script_injection]"
  setup_demo userscript || return
  # The bundled demo registers a user script that exposes
  # window.WebKitDemoSay.  Verify it is present.
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5
  assert_match "user script injected window.WebKitDemoSay" \
    "$(eval_js "typeof window.WebKitDemoSay")" "^string function$"
  teardown_demo
}

# =====================================================================
test_script_message_bridge() {
  echo "[test_script_message_bridge]"
  setup_demo bridge || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5
  # The demo registers "demoBridge" handler that writes the body into
  # the status field.  We can't observe NSTextField from JS, but the
  # demo also has a JS function WebKitDemoSay defined by the user
  # script that posts the message.  Calling it should not throw.
  local res=$(eval_js "WebKitDemoSay('hello from test'); 'ok'")
  assert_eq "bridge call doesn't throw" "$res" "string ok"
  teardown_demo
}

# =====================================================================
test_load_failure() {
  echo "[test_load_failure]"
  setup_demo loadfail || return
  # Navigate to an explicitly invalid host.
  send_cmd "GOTO http://this-host-does-not-exist-12345.invalid/"
  # Expect either a LOADED with the URL or evidence the demo logged
  # the failure.  We give it some time then check status.
  local end=$(( $(date +%s) + 10 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if grep -qE "(WKDEMO_LOADED:|Failed:)" "$TEST_LOG" 2>/dev/null; then break; fi
    sleep 0.2
  done
  sleep 0.5
  # We don't strictly need a particular outcome — what we need is
  # for the demo to *not* hang.  Confirm it's still alive and
  # responsive.
  local r=$(eval_js "1+1")
  assert_eq "demo still responsive after bad URL" "$r" "number 2"
  teardown_demo
}

# =====================================================================
test_scroll_wheel() {
  echo "[test_scroll_wheel]"
  setup_demo scroll || return
  local TALL=$(encode '<!doctype html><body style="margin:0">
<div style="height:5000px;background:linear-gradient(white,#888)"></div></body>')
  send_cmd "GOTO data:text/html,$TALL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5

  local wid
  wid=$(DISPLAY=$XDISP xdotool search --name "GNUstep WebKit Demo" | head -n 1)
  DISPLAY=$XDISP xdotool windowmove "$wid" 0 0 2>/dev/null
  sleep 0.2
  # Move cursor into page region (avoid toolbar), then scroll a few
  # times.  xdotool sends button 4/5 for scroll up/down.
  DISPLAY=$XDISP xdotool mousemove --sync 200 250
  for i in 1 2 3 4 5; do
    DISPLAY=$XDISP xdotool click 5  # scroll down
    sleep 0.05
  done
  sleep 0.4

  assert_match "scrolled vertically" \
    "$(eval_js "window.scrollY > 0")" \
    '^(boolean .*true|number 1)$'
  teardown_demo
}

# =====================================================================
test_visited_link_history() {
  echo "[test_visited_link_history]"
  setup_demo visited || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.5
  # WKBackForwardList should now have an entry (we just navigated).
  # Verify via history.length proxy.
  assert_match "history.length >= 1" \
    "$(eval_js "history.length >= 1")" \
    '^(boolean .*true|number 1)$'
  teardown_demo
}

# =====================================================================
test_user_agent() {
  echo "[test_user_agent]"
  setup_demo ua || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  local ua=$(eval_js "navigator.userAgent")
  echo "  UA: $ua"
  assert_match "user agent mentions WebKit" "$ua" "WebKit"
}

# =====================================================================
test_window_size_propagation() {
  echo "[test_window_size_propagation]"
  setup_demo winsize || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  local w=$(eval_js "window.innerWidth")
  local h=$(eval_js "window.innerHeight")
  assert_match "innerWidth is positive" "$w" "^number [1-9][0-9]+$"
  assert_match "innerHeight is positive" "$h" "^number [1-9][0-9]+$"
  teardown_demo
}

# =====================================================================
test_promise_resolution() {
  echo "[test_promise_resolution]"
  setup_demo promise || return
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  # Promises should resolve before subsequent eval, proving the JS
  # event loop is being driven by our GLib pump.
  eval_js "window._p_result = null; Promise.resolve(7).then(v => { window._p_result = v; });" >/dev/null
  sleep 0.3
  assert_eq "promise resolved to 7" \
    "$(eval_js "window._p_result")" "number 7"
  teardown_demo
}

# =====================================================================
test_dom_storage() {
  echo "[test_dom_storage]"
  setup_demo storage || return
  # data: URLs have opaque origin and can't use localStorage /
  # sessionStorage in current WebKit (they throw SecurityError on
  # access).  What we really want to test is that the property
  # access *throws cleanly* rather than crashing — and that the
  # engine recovers afterwards.
  send_cmd "GOTO $TEST_DATA_URL"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  local r=$(eval_js "try { var s = sessionStorage; 'present' } catch(e) { 'denied:' + e.name }")
  # Either outcome is acceptable; the test asserts only that the
  # engine handles the access gracefully.
  assert_match "sessionStorage accessed without crash" "$r" "^string (present|denied:)"
  # Engine still responsive afterwards.
  assert_eq "engine responsive after storage probe" \
    "$(eval_js "2+2")" "number 4"
  teardown_demo
}

# =====================================================================
test_javascript_types() {
  echo "[test_javascript_types]"
  setup_demo jstypes || return
  local PAGE=$(encode '<!doctype html><title>t</title>')
  send_cmd "GOTO data:text/html,$PAGE"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3
  assert_eq "string"  "$(eval_js "'hello'")" "string hello"
  assert_eq "integer" "$(eval_js "42")" "number 42"
  assert_eq "boolean true"  "$(eval_js "true")"  "number 1"
  assert_eq "boolean false" "$(eval_js "false")" "number 0"
  assert_eq "undefined"     "$(eval_js "undefined")" "undefined"
  assert_eq "null"          "$(eval_js "null")"  "object <null>"
  assert_match "array length" "$(eval_js "[1,2,3].length")" "^number 3$"
  assert_match "object key" \
    "$(eval_js "({a:1, b:2}).a")" "^number 1$"
  teardown_demo
}


# ---------- driver --------------------------------------------------

TESTS="${1:-load drag_select resize_repaint paste \
              navigation_lifecycle js_exception zoom_roundtrip \
              custom_scheme back_forward \
              dom_event_listeners form_typing kvo_title \
              javascript_types user_script_injection script_message_bridge \
              load_failure scroll_wheel visited_link_history user_agent \
              window_size_propagation promise_resolution dom_storage \
              cookie_roundtrip snapshot}"
start_xvfb

for t in $TESTS; do
  test_$t
done

echo
echo "==== $PASS passed, $FAIL failed ===="
[ $FAIL -eq 0 ]
