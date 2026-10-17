# Agent notes

`t3-headed-browser` is a single bash script. It writes a second bash script, the shim, into T3 Code's browser tool directory. Keep both POSIX-tool only: no extra runtime.

- Validate with `bash tests/test-shim.sh` and `shellcheck t3-headed-browser tests/test-shim.sh`. To lint the generated shim, run `install` in a test sandbox and lint the result.
- The tests use fake T3 homes, fake browsers and a fake X socket through `T3CODE_HOME`, `XDG_CONFIG_HOME` and `T3_HEADED_BROWSER_X11_DIR`. They must never touch a real `~/.t3`.
- Behavior and the reasons for it are documented in `docs/how-it-works.md`. Update it when the shim changes.
- Record user-visible changes in `CHANGELOG.md` under a new version, and bump `version` in the script.
