# t3-headed-browser

Make the browser panel of a remote [T3 Code](https://github.com/pingdotgg/t3code) server a real browser, so you can sign in to Google from it.

When a T3 Code server has no desktop app attached, for example `t3 serve` on a headless Linux box that you reach from the desktop app, the browser panel runs T3's bundled `chrome-headless-shell`. Google won't sign you in from it ("This browser or app may not be secure"), and it won't let you create an account there either. This tool swaps that shell for a small shim that runs a full Chromium-based browser (Google Chrome, Chromium, Brave or Microsoft Edge) as a normal visible browser on an X display. Your T3 version, settings and browser profiles stay as they are.

With the shim, Google sign-in reaches the password step, and you can use YouTube Studio, Google Cloud Console and similar sites in the panel. It doesn't try to beat bot checks. It makes the panel a normal browser for a person signing in to their own accounts.

Upstream report: [pingdotgg/t3code#20867](https://github.com/pingdotgg/t3code/issues/20867). Remove this tool once T3 ships a fix.

## Requirements

- Linux, running a T3 Code server whose browser panel uses the bundled server browser (nightly 0.0.46 or later).
- A full Chromium-based browser installed on the server: Google Chrome, Chromium, Brave or Microsoft Edge.
- An X display that the T3 service user can reach. A headless server can use Xvfb; see [`systemd/t3-xvfb.service`](systemd/t3-xvfb.service).
- bash, coreutils, awk and procps. systemd is optional; it re-applies the shim after T3 updates.

## Install

```sh
git clone https://github.com/Tarsow/t3-headed-browser.git
cd t3-headed-browser
install -Dm755 t3-headed-browser ~/.local/bin/t3-headed-browser

# Optional: a virtual display on :99, for a server without one.
install -Dm644 systemd/t3-xvfb.service -t ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now t3-xvfb.service

# Swap the shell, and re-apply the swap whenever T3 downloads a new one.
t3-headed-browser install            # or: install --browser /opt/google/chrome/chrome --display :99
install -Dm644 systemd/t3-headed-browser.path systemd/t3-headed-browser.service -t ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now t3-headed-browser.path
```

`install` picks the first browser it finds and saves your choice in `~/.config/t3-headed-browser/config`. If T3 has already started its headless browser, `install` stops it so that your next tab uses the new browser. Any server-browser tabs open at that moment close.

Check the result with `t3-headed-browser status`. Then open a tab in the browser panel and run `navigator.webdriver, typeof window.chrome, navigator.plugins.length` in it. You should get `false`, `"object"`, and a number above 0.

## Uninstall

```sh
systemctl --user disable --now t3-headed-browser.path
t3-headed-browser uninstall
rm ~/.local/bin/t3-headed-browser ~/.config/systemd/user/t3-headed-browser.{path,service}
```

## Caveats

- This is unofficial. It relies on T3 checking only that its pinned browser path is an executable file. A change in T3 could break it. If the browser or the display is missing, the shim falls back to the original shell, so the panel keeps working, but headless again.
- A visible browser uses more memory than the headless shell.

## More

- [How it works](docs/how-it-works.md): why Google rejects the shell, what the shim does, configuration and troubleshooting.
- Run the tests with `bash tests/test-shim.sh`. They use fake browsers and need no X server.

Canonical repository: [git.tarsow.dev/tarsow/t3-headed-browser](https://git.tarsow.dev/tarsow/t3-headed-browser). Mirrors: [GitHub](https://github.com/Tarsow/t3-headed-browser) and [Codeberg](https://codeberg.org/Tarsow/t3-headed-browser).

MIT licensed.
