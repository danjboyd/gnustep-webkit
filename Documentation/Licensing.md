# Licensing

A summary for downstream packagers, embedders, and anyone auditing
the licensing graph before shipping `gnustep-webkit` in a product.

## TL;DR

- This project is **LGPL-2.0-or-later** (matching GNUstep's
  `libs-gui` / `libs-OpenSave` house style).
- Every runtime dependency is either LGPL-compatible or permissively
  licensed.  There are **no copyleft incompatibilities** in the
  graph.
- Apple's `WKWebView` API surface is reimplemented from public
  documentation; no Apple source is incorporated.

## Dependency licenses

| Component | License | Role |
| --- | --- | --- |
| `gnustep-webkit` (this project) | LGPL-2.0-or-later | The framework |
| `libwpewebkit-2.0` (engine binary) | LGPL-2.0-or-later **and** BSD-2-Clause, dual | Real WebKit — JavaScriptCore + WebCore are LGPL (inherited from KHTML); Apple's WebKit additions are BSD-2-Clause; the shipped library is the dual-licensed combination |
| `libwpe` | BSD-2-Clause | Igalia's embedder interface (`wpe_view_backend`, `wpe_input_pointer_event`, ...) |
| `WPEBackend-FDO` | BSD-2-Clause | Igalia's FreeDesktop.org backend (the SHM/EGL exportable view backend we use) |
| `libsoup-3.0` | LGPL-2.1-or-later | HTTP / cookies (transitively required by WebKit) |
| `glib-2.0` / `gobject` / `gio` | LGPL-2.1-or-later | GObject runtime |
| `libwayland-server` | MIT | `wl_shm_buffer_*` accessors |
| `libgnustep-base` / `libgnustep-gui` | LGPL-2.0-or-later | The host |

References:

- [Licensing WebKit (webkit.org)](https://webkit.org/licensing-webkit/)
- [WebKit's official Licensing.md](https://github.com/webkit/Documentation/blob/main/docs/Other/Licensing.md)
- [WPE FAQ — "WPE is published under a mix of LGPLv2 and BSD licenses"](https://wpewebkit.org/about/faq.html)
- [libwpe (BSD-2-Clause)](https://github.com/WebPlatformForEmbedded/libwpe)
- [WPEBackend-FDO](https://github.com/Igalia/WPEBackend-fdo) — BSD-2-Clause

## Compatibility reasoning

**LGPL-2.0+ ↔ LGPL-2.1+.**  Both clauses include "any later version"
language, so they reconcile at a common version (LGPL-2.1 or LGPL-3,
depending on whose terms the user invokes).  No conflict.

**LGPL ↔ BSD-2-Clause.**  BSD-2-Clause is permissive with attribution
only; it can be incorporated into LGPL projects without conflict.
WebKit's dual license was explicitly chosen by Apple/the WebKit
contributors precisely so downstream LGPL projects (like ours) could
link against it without having to choose the BSD horn.

**Dynamic linking under LGPL.**  This project links *dynamically* to
every dependency in the table above — no static linking, no vendored
source.  Section 6 of the LGPL permits exactly this and requires only
that end users be able to relink against a modified version of the
library, which dynamic linking already provides.

**Apple `WK*` API surface.**  The class names, method signatures, and
delegate protocols are reproduced from Apple's public WebKit
documentation.  Per the US Supreme Court's holding in *Google LLC v.
Oracle America Inc.* (2021), reimplementing a published API is fair
use; the surface itself is not copyrightable.  None of Apple's
implementation source is incorporated in this project.

## What downstream users can do

| Downstream license | Can link `gnustep-webkit` dynamically? | Notes |
| --- | --- | --- |
| GPL-2.0+ application | Yes | LGPL-2.0+ → GPL-2.0+ relicensing is explicitly permitted by LGPL §3 |
| GPL-3.0+ application | Yes | Same, at GPL-3 |
| LGPL application/library | Yes | Trivially |
| MIT / BSD / Apache application | Yes | Dynamic linking only; modifications to `gnustep-webkit` itself must remain LGPL |
| Proprietary closed-source application | Yes, **with dynamic linking** | Standard LGPL terms: ship `libWebKit.so` separately or as an installable system library; end users must be able to substitute a different build of the library |

The same rules apply transitively to `libwpewebkit`, `libwpe`,
`WPEBackend-FDO`, `glib`, and `libsoup`, all of which have the same
or more-permissive terms.

## What this project does *not* include

- No Apple WebKit source code.  The engine binary
  (`libwpewebkit-2.0.so`) is a separate system library provided by
  the user's distribution.
- No vendored copies of GPL- or AGPL-licensed code.  Every
  dependency above is either LGPL or permissive.
- No Apple-trademarked names beyond the reimplemented API class names
  (Apple does not claim trademark protection on `WKWebView` as a
  class name; the trademark "WebKit" applies to the engine project
  hosted at webkit.org, not to consumers using the engine).

## Reporting license concerns

If you spot a licensing issue — a file with a stricter license header
than the project's, an attribution we owe and missed, a sublicense we
should be declaring — please file an issue on the GitHub repository
flagged as `licensing` so it can be addressed quickly.
