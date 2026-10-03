# Browser checks with the chrome-devtools MCP

Reach for it for any UI/UX review, visual or layout audit, rendering or responsive check of a running app, not only for debugging.

- Phone widths: `resize_page` is held at Chrome's minimum window width, so `innerWidth` stays wider than asked. Use `emulate` with `viewport: "WxHxDPR,mobile,touch"` (`"390x844x3,mobile,touch"`, desktop `"1366x768x1"`) and confirm `innerWidth` before measuring.
- Screenshots: a `filePath` outside the MCP's allowed roots fails with "Access denied", and the session scratchpad is outside them. Omit `filePath`; a full-page shot lands in `$TMPDIR/chrome-devtools-mcp-*/screenshot.png`. Downscale high-DPR full pages (`sips -Z 2400 <src> --out <dst>`) before reading them.
- A reported layout bug: reproduce at the reporter's viewport (a screenshot's pixel width divided by its DPR, 2 for a Retina Mac), then check the breakpoints the layout keys on and the widest common width. Test a viewport-independent fix alone before adding a second.
- After a fix motivated by a trace or audit number (CLS, Lighthouse), re-run that same measurement. When the page under test is a dev server, say so, and check the built app for what dev skips (CSP headers, font pipeline, performance).
- Subagents that open pages (named `isolatedContext`s) leave them open: their briefs end with `close_page` on each, and the parent runs `list_pages` before its next browser step.
