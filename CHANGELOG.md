# Changelog

## 0.1.1

- The headed browser no longer quits at startup when T3 runs inside a desktop session, such as the T3 Code desktop app on GNOME. The shim used to keep the session's `XAUTHORITY`, which has no cookie for the configured display, so the browser couldn't connect to Xvfb. It now keeps an inherited `XAUTHORITY` only for the display it belongs to and otherwise uses `~/.Xauthority`.
- T3's HTML previews work again with the shim installed. They launch the shell with `--headless=new`, and the shim now runs the original headless shell for them instead of the headed browser, which never finished loading the page.
- Passkey sign-ins no longer freeze the page. The headed browser showed its passkey prompt outside the page, where the browser panel can't show it, and the page stopped responding until the prompt was dismissed. The shim now turns off WebAuthn, so sites such as Google offer a password or another sign-in method instead.

## 0.1.0 (2026-10-17)

First release.

- `t3-headed-browser install` swaps T3 Code's bundled `chrome-headless-shell` for a shim. The shim runs a full Chromium-based browser (Google Chrome, Chromium, Brave or Microsoft Edge) headed on an X display, so Google sign-in and sign-up work in the browser panel of a remote T3 server.
- Persistent profiles survive T3 closing a profile's first page. The browser starts windowless, and its first page opens through a second invocation.
- The shim falls back to the original headless shell when the browser or the X display is missing.
- `t3-headed-browser.path` re-applies the shim when T3 downloads a new shell version. It also stops a headless browser that T3 launched before the shim landed.
- `uninstall` restores the original binaries, and `status` shows the configuration and each shell's state.
- Includes an example `t3-xvfb.service` for servers without a display.
