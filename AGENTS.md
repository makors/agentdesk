# AGENTS.md

Guide for any AI agent or human working **in** this repo. For what agentdesk is and
how to install it, read [`README.md`](README.md).

## What this is

`agentdesk` lets an AI agent use a real macOS desktop at the same time as the human.
It runs an app on a **hidden virtual display** in the corner of the screen and drives it
by process id, window id, and Accessibility. The core idea: give the agent its own
addressed workspace and never touch the shared keyboard, pointer, or focus (the HID seat).
Any dialog that lands on the user's screen is moved to the hidden desk in about one frame.

## Repo layout

- `cli/agentdesk` — the CLI. A single Python script; the main entry point.
- `src/*.m` — the native tools. Single-file Objective-C, one binary each:
  - `oracle.m` — passive measurement (focus, pointer, windows on the main display). No input.
  - `axact.m` — exact-window Accessibility actor (set value, insert, press, menu, move).
  - `agentdesk-daemon.m` — the relocator that moves stray dialogs onto the hidden desk.
  - `hidden-display.m` — creates or reuses the hidden virtual display.
  - `src/experiments/*.m` — throwaway probes from the research; not shipped.
- `mcp/agentdesk_mcp.py` — stdio MCP server. Wraps the CLI. Tools: `desk_open`, `desk_close`, `desk_status`.
- `plugins/agentdesk/` — the Codex plugin: `.mcp.json`, `.codex-plugin/plugin.json`, and
  `skills/agentdesk/SKILL.md` (the agent-facing workflow).
- `Formula/agentdesk.rb` — the Homebrew formula.
- `docs/` — `RESEARCH-LOG.md` (the evidence and technical model) and `evidence/`.
- `assets/` — logos and banner.

## Build & run

You need the Xcode command line tools (`clang`).

```
./build.sh                   # compiles the native tools into ./bin (git-ignored)
./cli/agentdesk up           # start the hidden desk + relocator daemon
./cli/agentdesk launch TextEdit   # open an isolated hidden copy; prints its pid + window id
./cli/agentdesk status
./cli/agentdesk down         # stop the daemon (launched app instances keep running)
```

Whatever launches the tools (your terminal, or the ChatGPT app for the MCP) needs
**Accessibility** permission: System Settings > Privacy & Security > Accessibility.

## How an agent uses it at runtime

Short version — the full workflow is in
[`plugins/agentdesk/skills/agentdesk/SKILL.md`](plugins/agentdesk/skills/agentdesk/SKILL.md).

1. `desk_open({ app })` — opens the app on the hidden desk. Returns `pid`, `window_id`, `mode`.
2. Drive the returned pid / window in the **background**. Never bring the app to the front,
   never click to activate, never move the user's pointer.
3. `desk_close({ desk_id: pid })` — restores and un-watches the app. It **never quits an app
   the user already had open** (an adopted `shared_instance`); it only quits copies agentdesk launched.

## Conventions & gotchas

- **macOS only.** Uses private WindowServer / SkyLight and Accessibility APIs; a future
  macOS may need changes.
- **Native tools are single-file ObjC**, compiled directly with `clang` (see `build.sh` and
  the formula). Keep each tool one self-contained `.m` file.
- **Runtime state lives under `~/.agentdesk`** (override with `AGENTDESK_HOME`): the daemon
  pid, watched agents, hidden-display state, and the relocation log.
- **Only Accessibility actuates.** No synthetic keyboard or pointer events, no activation.
- **Single-copy apps (Adobe)** are adopted, not re-launched (`mode: shared_instance`), and
  are safe only when the user is not using that same app.
- **Canvas / pixel apps (Photoshop, Illustrator)** expose no drivable window until a document
  is open. Open or create a document first; prefer the app's own script engine over pixel clicks.
- **Keep changes small** and match the plain, direct tone of the README.

## How to verify you didn't disturb the user

Run `oracle` (`src/oracle.m`) while an agent action happens. It passively records the user's
desktop state and needs no input. A clean run shows **zero** frontmost changes, focus changes,
pointer jumps, windows appearing on the main display, and pointer entries into the hidden
display. See `docs/RESEARCH-LOG.md` for the measured baselines.
