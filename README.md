<div align="center">

<img src="assets/logo.svg" width="132" height="132" alt="agentdesk logo" />

# agentdesk

**A second desk on your Mac, out of your way.**

Let an AI agent use your Mac at the same time as you. It uses your real apps, files,
settings, and sign-ins. It does not make a virtual machine or a copy.
You keep typing and clicking. The agent works on a hidden desk you never see.

</div>

---

## The problem

An agent that drives your Mac normally fights you for one keyboard and one pointer.
It steals your focus. Its windows and file dialogs jump in front of your work.

macOS sends the keyboard to one window **per process**. Two windows in one process
cannot get separate keystrokes. So an earlier idea, one hidden monitor, did not help:
when the agent opened a file dialog in the same app you used, your typing went to the dialog.

## The idea

`agentdesk` gives the agent its **own process** of the app. Keyboard routing is then
independent, because macOS routes per process, not per app. The agent's windows live on a
**hidden display** placed at the corner of your screen, where the pointer cannot reach them.
A small background service moves any dialog the agent opens off your screen in about one frame.

`agentdesk` does not do the clicking and typing. Your agent (for example Codex background
computer use) does that, by process id and window id. `agentdesk` only makes a safe place
and keeps it out of your way.

## What is verified

Measured while the user typed, under a hard load of file dialogs and floating panels:

- The agent's process **never held the user's keyboard focus**.
- **No agent window rested on the user's screen.** Dialogs moved to the hidden display in
  **1 to 2 milliseconds**, below one frame.
- **The pointer never moved.** The front app never changed.
- The pointer **cannot cross into the hidden display**, because it touches the main screen at one corner only (0 pixels of shared edge).

Full method and numbers: [`docs/RESEARCH-LOG.md`](docs/RESEARCH-LOG.md).

## How it works

1. `agentdesk up` makes the hidden display and starts the mover.
2. `agentdesk launch <App>` starts a hidden, separate copy of the app and returns its
   process id and window id.
3. Your agent drives that process id and window id with its own background computer use.
4. Any dialog the agent opens moves off your screen by itself.
5. `agentdesk down` removes the hidden display and stops the mover.

## Install

```
git clone https://github.com/makors/agentdesk
cd agentdesk
./build.sh          # needs the Xcode command line tools; makes ./bin
```

Give the launching terminal (or a shipped signed app) Accessibility permission once, in
System Settings, under Privacy and Security.

## Use

```
./cli/agentdesk up
./cli/agentdesk launch TextEdit          # prints {pid, window_id} on the hidden desk
./cli/agentdesk act menu <pid> 'File>Open…'   # the dialog moves off your screen by itself
./cli/agentdesk status
./cli/agentdesk down
```

To open a known file with no dialog at all: `./cli/agentdesk launch TextEdit --file /path`.

## Hook up to Codex computer use

`agentdesk` does not replace your agent's computer use. It runs at the start and the end.

1. `agentdesk up` once.
2. `agentdesk launch <App>` returns the isolated process id and window id.
3. Point Codex background computer use at that process id and window id.
4. Dialogs move away by themselves. You are never interrupted.

The same shape fits a small MCP server with two tools, `desk_open` and `desk_close`.
Many desks work at once, because the mover watches a list of process ids.

## The browser is different

Chrome does not allow a second process on one profile. Drive Chrome through the browser
protocol (the Claude in Chrome extension), not through key events, because Chrome drops
background key events. The mover still catches any native Chrome dialog.

## Honest limits

- Canvas, 3D, and game apps show no accessibility tree. They need pointer clicks that
  briefly bring the app to the front. Out of scope.
- System permission dialogs are drawn by macOS on your screen. They cannot be moved.
- All desks share one login session, so they share the clipboard and global state.
  Many desks means many isolated window groups, not many operating systems.
- The hidden display uses private macOS interfaces. A future macOS may need changes.

## Layout

```
cli/agentdesk            the command you run
src/hidden-display.m     the corner hidden display
src/agentdesk-daemon.m   the dialog mover
src/axact.m              exact-window Accessibility actor (no key or pointer events)
src/oracle.m             passive checker: proves your focus and pointer did not move
src/experiments/         the fixtures that produced the evidence
docs/RESEARCH-LOG.md     every experiment, mechanism, and result
```

<div align="center">
<sub>Built and verified on macOS 26. Uses private WindowServer and Accessibility interfaces.</sub>
</div>
