<div align="center">

<img src="assets/logo.svg" width="120" height="120" alt="agentdesk" />

# agentdesk

**A second desk on your Mac, out of your way.**

Let an AI agent use your Mac at the same time as you.
It uses your real apps, files, and sign-ins. No virtual machine. No copy.
You keep working. The agent works on a hidden desk you never see.

</div>

---

## What it does

An agent that drives your Mac normally fights you for the keyboard and pointer, steals your
focus, and drops its windows on top of your work.

`agentdesk` runs the app on a **hidden display** in the corner of your screen, where the pointer
cannot reach it. The agent drives that app by process id, window id, and Accessibility. A
background service moves any dialog the agent opens off your screen in about one frame. The agent
does the work; `agentdesk` keeps it out of your way.

Your screen, focus, and pointer stay yours.

## Install

Homebrew:

```
brew tap makors/agentdesk https://github.com/makors/agentdesk
brew install agentdesk
```

Or from source (needs the Xcode command line tools):

```
git clone https://github.com/makors/agentdesk
cd agentdesk && ./build.sh
```

Then grant **Accessibility** once. The tools move and read windows, so whatever launches them
needs permission: **System Settings → Privacy & Security → Accessibility**. Turn on your terminal
(for the CLI) or the app that runs the MCP server.

## Use

```
agentdesk up                 # start the hidden desk
agentdesk launch TextEdit    # open an isolated copy; prints its pid + window id
agentdesk status
agentdesk down               # remove the hidden desk
```

Hand the printed pid and window id to your agent's computer use. Drive the app in the background;
do not bring it to the front. Any dialog it opens moves off your screen by itself.

Open a file with no dialog at all:

```
agentdesk launch TextEdit --file /path/to/file
```

## Use from an agent (MCP)

Print a paste-ready MCP config block and add it to your agent's config, then restart the app:

```
agentdesk mcp
```

The agent gets three tools: `desk_open`, `desk_close`, and `desk_status`. Call
`desk_open({ app: "TextEdit" })`, drive the returned pid in the background, then `desk_close`.

**Codex plugin.** To add agentdesk to Codex with its own icon and an auto-loading `agentdesk`
skill:

```
codex plugin marketplace add makors/agentdesk
codex plugin add agentdesk@makors
```

## How it works

- **A separate process.** macOS routes the keyboard per process, so the agent's copy never takes
  keys meant for your window. Apps that refuse a second copy (like Adobe) are adopted and isolated
  instead.
- **A corner hidden display.** It touches your screen at one point, so the pointer cannot wander
  into it.
- **A dialog mover.** Any agent window that lands on your screen is moved to the hidden desk in
  about one frame.
- **Accessibility only.** The agent acts through the Accessibility layer. It sends no key or
  pointer events to your session and never brings an app to the front.

Measured on macOS 26 while the user typed: focus never stolen, pointer never moved, no agent
window left on the user's screen. See [`docs/RESEARCH-LOG.md`](docs/RESEARCH-LOG.md).

## Limits

- A faint flash of a few milliseconds can show when a heavy app first launches.
- Single-copy apps (Adobe) share one process. Safe only when you are not using that app yourself;
  `desk_open` warns you.
- The browser needs its own path (a browser extension), not built yet.
- Canvas and game apps, and macOS permission dialogs, are out of scope.
- Uses private macOS interfaces. A future macOS may need changes.

## License

MIT. See [LICENSE](LICENSE).
