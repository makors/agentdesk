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

An agent that drives your Mac normally fights you for the keyboard and the pointer.
It steals your focus. Its windows and file dialogs land on top of your work.

`agentdesk` gives the agent its **own copy** of an app on a **hidden display** in the
corner of your screen, where the pointer cannot reach it. A small background service
moves any dialog the agent opens off your screen in about one frame. Your agent
(Codex, or any tool) does the clicking; `agentdesk` just keeps it out of your way.

## Setup

**1. Install**

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

**2. Grant Accessibility (once)**

The tools move and read windows, so the app that launches them needs permission.
Open **System Settings → Privacy & Security → Accessibility** and turn on your
terminal (for command-line use) or the ChatGPT app (for the Codex MCP).

**3. (Optional) Wire into Codex / the ChatGPT app**

Print a paste-ready config block:

```
agentdesk mcp
```

Paste it into `~/.codex/config.toml`, then restart the app. The agent gets three
tools: `desk_open`, `desk_close`, `desk_status`.

## Install as a Codex plugin (mentionable)

Make agentdesk show up in the ChatGPT / Codex app with its own icon:

```
brew install agentdesk    # provides the MCP server
codex plugin marketplace add makors/agentdesk
codex plugin add agentdesk@makors
```

Restart the app. The plugin appears with the three tools `desk_open`, `desk_close`,
`desk_status`. (The bundled server path assumes Apple Silicon Homebrew at
`/opt/homebrew`; on Intel, edit `plugins/agentdesk/.mcp.json` to `/usr/local`.)

## Use

```
agentdesk up                 # start the hidden desk
agentdesk launch TextEdit    # open an isolated copy; prints its pid + window id
agentdesk status
agentdesk down               # remove the hidden desk
```

Hand the printed pid and window id to your agent's computer use. Drive it in the
background; do not bring it to the front. Any dialog it opens moves off your screen
by itself. To open a file with no dialog at all:

```
agentdesk launch TextEdit --file /path/to/file
```

From Codex, the same thing is `desk_open({app: "TextEdit"})`, then drive the
returned pid, then `desk_close`.

## How it works

- **A separate process.** macOS routes the keyboard per process, so the agent's copy
  never takes keys meant for your window. Apps that refuse a second copy (like Adobe)
  are adopted and isolated instead.
- **A corner hidden display.** It touches your screen at one point, so the pointer
  cannot wander into it.
- **A dialog mover.** Any agent window that lands on your screen is moved to the
  hidden desk in about one frame.
- **Accessibility only.** The agent acts through the accessibility layer. It sends no
  key or pointer events to your session and never brings an app to the front.

Measured on macOS 26 while the user typed: focus never stolen, pointer never moved,
no agent window left on the user's screen. See [`docs/RESEARCH-LOG.md`](docs/RESEARCH-LOG.md).

## Limits

- A faint flash of a few milliseconds can show when a heavy app first launches.
- Single-copy apps (Adobe) share one process. Safe only when you are not using that
  app yourself. `desk_open` warns you.
- The browser needs its own path (a browser extension), not covered here yet.
- Canvas and game apps, and macOS permission dialogs, are out of scope.
- Uses private macOS interfaces. A future macOS may need changes.

## License

MIT. See [LICENSE](LICENSE).
