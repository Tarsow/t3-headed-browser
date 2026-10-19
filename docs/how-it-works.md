# How it works

## How T3 Code runs its server browser

T3 Code's browser panel renders a tab in one of two places:

- **In the desktop app.** If the desktop app launched the server as its own child process, tabs render in the desktop app's webview.
- **On the server.** Otherwise the server drives its own browser through Playwright. This covers `t3 serve` as a service, remote environments, the web app and mobile.

For the second case T3 downloads a pinned [`chrome-headless-shell`](https://developer.chrome.com/blog/chrome-headless-shell) to:

```
~/.t3/tools/chrome-headless-shell/<platform>/<version>/chrome-headless-shell
```

It launches that binary with `headless: true`, and offers no setting for another executable or for headed mode. Before using an installed binary, T3 checks only that the file at that path is executable. This tool relies on that check.

## Why Google rejects the shell

[pingdotgg/t3code#16963](https://github.com/pingdotgg/t3code/pull/16963) gave server tabs a consistent `Chrome` user agent and client hints and turned off `navigator.webdriver`. That is enough for Google search and most bot checks, but Google account sign-in still redirects to `/v3/signin/rejected`, and sign-up ends at `/signup/error/1`. A page can still see two differences: in `chrome-headless-shell`, `window.chrome` is undefined and `navigator.plugins` is empty.

Measured with Playwright 1.60 and T3's launch options, from one machine and IP:

| Browser | `window.chrome` | plugins | Google sign-in after the email step |
| --- | --- | --- | --- |
| `chrome-headless-shell` 154, as T3 runs it | undefined | 0 | rejected |
| Brave 1.93 (Chromium 151), `--headless`, `HeadlessChrome` user agent | object | 7 | rejected |
| Brave 1.93, `--headless`, normal user agent | object | 7 | password step |
| Brave 1.93, headed on Xvfb | object | 7 | password step |

A full Chromium build passes, and the headless shell doesn't. This tool runs the full browser headed, because nothing in that mode reports it as headless.

## What the shim does

`t3-headed-browser install` renames each installed `chrome-headless-shell` to `chrome-headless-shell.real` and writes a bash shim in its place. The shim writes in the browser path and display you chose at install time. When T3 launches the shim, it does the following:

1. **Version checks and HTML previews.** For `--version`, and for `--headless=new`, it runs the original binary. T3's HTML previews (`html_preview` and `html_render`) launch the shell directly with `--headless=new`. They render the agent's own pages, so they don't need a real browser, and a headed one never finishes loading them. Playwright, which runs the browser panel, passes plain `--headless`.
2. **Fallback.** If the browser isn't executable, or there is no X socket for the display (`/tmp/.X11-unix/X<N>`), it runs the original binary with the original arguments. The panel then keeps working, headless.
3. **Flag cleanup.** Otherwise it drops `--headless`, `--headless=*` and `--hide-scrollbars`, sets `DISPLAY`, and sets `XAUTHORITY`. It keeps an inherited `XAUTHORITY` only when the inherited `DISPLAY` is the configured display; otherwise it uses `~/.Xauthority`. A T3 server started from a desktop session inherits that session's auth file, which has no cookie for Xvfb.
   It also turns off WebAuthn by adding `WebAuth` to `--disable-blink-features`, merged into Playwright's own copy of that switch because Chromium keeps only the last one. A headed browser answers a passkey request with its own prompt, outside the page, so the browser panel never shows it, and the page stops responding until someone dismisses it. With WebAuthn off, sites such as Google offer a password or another sign-in method instead. Passkeys don't work in the panel either way.
4. **Throwaway contexts** (incognito and isolated tabs). Playwright passes `--no-startup-window` for these, and the shim simply `exec`s the browser.
5. **Persistent profiles** (the Default profile and named profiles). T3 calls `launchPersistentContext`. It then closes every page the browser started with, before opening its own tab. A headless shell survives that, but a headed browser quits when its last window closes, and T3's next step fails with `browserContext.newPage: Target page, context or browser has been closed`. `--keep-alive-for-test` doesn't prevent this. So the shim:
   - starts the browser with `--no-startup-window`, which keeps it running with no windows;
   - waits until the profile's `SingletonLock` points to that browser's PID (or a child of it);
   - opens the first page with a second invocation, `browser --user-data-dir=<same profile> about:blank`. Chromium hands that request to the running instance, which satisfies Playwright's wait for an initial page;
   - waits for the browser, passes on `TERM`, `INT` and `HUP`, and exits with the browser's status.

The shim receives Playwright's `--remote-debugging-pipe` file descriptors (3 and 4) and passes them on unchanged. The second invocation runs with them closed.

## Staying applied after T3 updates

T3 downloads a new pinned shell into a staging directory, then renames it into `~/.t3/tools/chrome-headless-shell/linux64/<version>`. `t3-headed-browser.path` watches that directory and runs `t3-headed-browser install` when it changes. That command shims the new binary with your saved browser and display.

T3 usually launches a freshly downloaded shell before the watcher acts. So whenever `install` shims a binary for the first time, it also stops any running headless browser started from that binary. T3 relaunches it, through the shim, on the next tab.

The path unit watches `linux64`; on ARM64 hosts, change it to `linux-arm64`. It also assumes T3's home is `~/.t3`. If yours differs, edit the unit, and set `T3CODE_HOME` when you run `t3-headed-browser` by hand.

## Configuration

| Setting | Where |
| --- | --- |
| Browser executable | `install --browser PATH`. Saved as `browser=` in `${XDG_CONFIG_HOME:-~/.config}/t3-headed-browser/config`. |
| X display | `install --display :N`. Saved as `display=`; the default is `:99`. |
| Per-launch override | The environment variables `T3_HEADED_BROWSER` and `T3_HEADED_BROWSER_DISPLAY`, read by the shim at launch time. They must be set in the T3 service's environment. |
| T3 home | `T3CODE_HOME`, default `~/.t3`. |

Point `--browser` at the real binary, such as `/opt/google/chrome/chrome` or `/opt/brave.com/brave/brave`, rather than at a launcher script in `/usr/bin`. The shim then watches the browser's own PID. A launcher that runs the browser as a child process still works. Snap-packaged browsers are untested.

After changing the configuration, run `t3-headed-browser install` again. Shims that are already installed are rewritten in place.

## Troubleshooting

- **`t3-headed-browser status` says `display: :99 (not running)`.** Start your X server, for example `systemctl --user start t3-xvfb.service`. Until then, tabs use the headless shell.
- **Tabs still look headless.** T3 keeps a headless browser it already started running, even with no tabs open. Stop it with `pkill -f chrome-headless-shell`. That closes its tabs. The next tab you open starts through the shim.
- **`browserContext.newPage: Target page, context or browser has been closed`.** Something other than this shim runs a headed browser for T3, or the browser exited at startup. Run the browser by hand on the same display to see its errors: `DISPLAY=:99 /opt/brave.com/brave/brave --user-data-dir=$(mktemp -d) about:blank`.
- **Profile from a newer browser.** T3's profiles live in `~/.t3/userdata/server-browser/profiles/`. If the browser you configured is older than the Chromium that last wrote a profile, it may refuse that profile. Back the profile up first, then move it aside or use a newer browser.
- **Re-application log.** Run `journalctl --user -u t3-headed-browser.service`.
