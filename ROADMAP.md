# Roadmap

This tool is a stopgap. Upstream, [pingdotgg/t3code#20867](https://github.com/pingdotgg/t3code/issues/20867) asks T3 Code to do one of the following:

- run a full Chrome or Chromium build for its server browser;
- let operators choose the server browser executable and headed mode;
- render remote environments' tabs in the connected desktop app.

Once any of these ships, this project will document the switch and be archived.

Until then, one possible improvement is to start a private Xvfb per launch, so no long-running display service is needed.
