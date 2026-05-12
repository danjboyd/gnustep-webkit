# Tests

Two suites, both driven by `make` and runnable on a developer machine
without any extra infrastructure.

## Unit tests — `Tests/Unit/`

Pure Objective-C tests that exercise the value-type classes
(`WKWebViewConfiguration`, `WKBackForwardList`, `WKUserContentController`,
`WKUserScript`, `WKPreferences`, `WKContentWorld`, …) and a handful of
internal initializers via `Tests/Unit/wktests.m`.  No engine, no
Xvfb, no display required.

```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make -C Tests/Unit run
```

Current count: **119 assertions across 28 test functions.**  Adding a
new test is a single function in `wktests.m` plus one line in `main`.

What each test function covers is documented inline at the top of the
function.

## Integration tests — `Tests/run_tests.sh`

End-to-end tests that boot an Xvfb, start `gpbs`, launch a fresh
`WebKitDemo.app`, drive it through a stdin command channel
(`GOTO` / `EVAL` / `RESIZE` / `COOKIE_SET` / `COOKIE_LIST` /
`SNAPSHOT` / `QUIT`), synthesise mouse / keyboard events with
`xdotool`, and assert against the engine's response (mostly through
JavaScript evaluation of expected DOM / window state).

```sh
./Tests/run_tests.sh                # all tests
./Tests/run_tests.sh paste          # one test by name
WKDEMO_KEEP_LOGS=1 ./Tests/run_tests.sh paste     # keep /tmp/wkdemo-tests.XXX/
WKDEMO_TRACE_EVENTS=1 ./Tests/run_tests.sh drag_select  # per-event logging
```

Current count: **43 assertions across 22 test functions.**

What each tests:

| Test | What it asserts |
| --- | --- |
| `load` | innerText of a known-content data: URL is populated |
| `drag_select` | mousedown + drag (via JS shim) extends selection; programmatic selection separately works; selection clears |
| `resize_repaint` | `window.innerWidth` follows window-frame resize commands |
| `paste` | Ctrl+C copy via NSPasteboard, Ctrl+V into a different input recovers the same text |
| `navigation_lifecycle` | `document.readyState` reaches "complete"; `performance.timing.loadEventEnd` > 0 |
| `js_exception` | `throw new Error("…")` surfaces as `ERROR` from `evaluateJavaScript:`; engine recovers afterwards |
| `zoom_roundtrip` | `window.devicePixelRatio` is a positive number |
| `custom_scheme` | `myapp://` navigation invokes the host's `WKURLSchemeHandler` and the served HTML actually renders |
| `back_forward` | history.length > 1 after two navigations |
| `dom_event_listeners` | click + mousedown + mouseup + mousemove DOM events all fire from xdotool input |
| `form_typing` | xdotool-typed text reaches an `<input>` via the engine's keyboard event path |
| `kvo_title` | `document.title` set by `<title>` tag is reflected back |
| `javascript_types` | `string`, `number`, `true`/`false`, `null`, `undefined`, arrays, object property lookup all convert correctly |
| `user_script_injection` | the demo's `WKUserScript` is injected before document-ready |
| `script_message_bridge` | `window.webkit.messageHandlers.NAME.postMessage(…)` does not throw |
| `load_failure` | navigation to an invalid host doesn't hang the demo |
| `scroll_wheel` | xdotool scroll moves `window.scrollY` |
| `visited_link_history` | `history.length` >= 1 after a navigation |
| `user_agent` | `navigator.userAgent` contains "WebKit" |
| `window_size_propagation` | `window.innerWidth` and `window.innerHeight` are positive |
| `promise_resolution` | A resolved Promise's `then` callback runs (proves the GLib pump is driving the JS event loop) |
| `dom_storage` | `sessionStorage` either resolves or throws cleanly on a data: URL |
| `cookie_roundtrip` | `WKHTTPCookieStore` `setCookie:` + `getAllCookies:` returns the cookie we set |
| `snapshot` | `takeSnapshotWithConfiguration:` returns an `NSImage` with a positive size |

### Adding a new integration test

Each test is a shell function in `run_tests.sh` following this
pattern:

```bash
test_my_new_thing() {
  echo "[test_my_new_thing]"
  setup_demo my_thing || return

  send_cmd "GOTO data:text/html,$(encode '<html>...</html>')"
  wait_for "WKDEMO_LOADED:" 10 || { teardown_demo; FAIL=$((FAIL+1)); return; }
  sleep 0.3

  assert_match "predicate name" "$(eval_js "...")" '^pattern$'

  teardown_demo
}
```

Then add `my_new_thing` to the `TESTS=` list near the bottom of the
file.

### Test-only protocol on demo stdin

When the demo is launched with `WKDEMO_TEST_MODE=1` it reads
line-oriented commands on stdin and writes structured replies to
stderr.  Commands:

| Command | Effect | Reply on stderr |
| --- | --- | --- |
| `GOTO <url>` | navigate the WKWebView | `WKDEMO_ACK: GOTO` then later `WKDEMO_LOADED: <url>` on completion |
| `EVAL <js>` | call `evaluateJavaScript:completionHandler:` | `WKDEMO_EVAL_RESULT: <type> <repr>` |
| `STATE` | dump view geometry + URL + title + loading flag | `WKDEMO_STATE: …` |
| `RESIZE <w> <h>` | resize the demo window | `WKDEMO_ACK: RESIZE want=WxH got_win=… web=…` |
| `WEBVIEW_RESIZE <w> <h>` | resize the WKWebView directly | `WKDEMO_ACK: WEBVIEW_RESIZE …` |
| `COOKIE_SET name=value;.domain` | put a cookie in the store | `WKDEMO_ACK: COOKIE_SET` |
| `COOKIE_LIST` | dump WKHTTPCookieStore contents | `WKDEMO_COOKIE_RESULT: name@domain=value,…` |
| `SNAPSHOT` | call `takeSnapshotWithConfiguration:` | `WKDEMO_SNAPSHOT_RESULT: image:WxH` or `nil` / `error:…` |
| `QUIT` | clean shutdown via `[NSApp terminate:]` | (process exits) |

Test mode also disables the demo's startup auto-load (`gnustep.org`),
which would otherwise race with the harness's `GOTO`.

## CI

`.github/workflows/ci.yml` runs the unit suite on Debian 13
(container) and on `ubuntu-24.04` on every push and pull request.
Integration tests are not yet in CI because the Xvfb + xdotool +
gpbs orchestration takes ~3 minutes per test run and the runners
have lower priority for x11 setup.  Easy follow-up.

## What's not covered

Honest gaps remaining as of v0.1.0:

- `WKContentRuleListStore` JSON compilation paths (no test exercises the actual content blocker bytecode)
- `WKDownload` lifecycle end-to-end (we test the API surface; not a real download completing)
- `WKContentWorld` isolation (engine doesn't actually isolate worlds in our build, so testing the API distinction is hollow)
- Cursor shape changes on hover
- Hit-test aware context menu items
- File chooser callback firing (the NSOpenPanel is modal which trips up xdotool sequencing)
- Memory leak / valgrind sweeps
- Multi-distro CI matrix beyond Debian/Ubuntu
- Code coverage measurement (no gcov/lcov gating)
