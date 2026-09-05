# Research log: concurrent agent use of this Mac (round 3)

Date: 2026-09-05. Host: Apple M4 Pro, macOS 26.5.2 (25F84), SIP enabled. Main display 1512x982 (Retina), hidden virtual display 1920x1200 at (1512,0) created by the round-2 Monitor manager (pid 5432, no managed windows).

Tools in this folder (`bin/`, sources in `src/`):
- `oracle` — passive measurement: frontmost app, system-wide focused element (Accessibility), pointer position/jumps, pointer entering the hidden display, windows appearing on the visible display, HID idle time. No taps, no input.
- `routing-lab` — disposable two-window AppKit fixture on the hidden display for key-routing experiments.
- `axact` — exact-window Accessibility actor for any process (owner check + `_AXUIElementGetWindow` identity + membership re-check). No keyboard or pointer events.

Environment notes:
- Accessibility was not granted to the `claude` binary at first (process chain tmux → zsh → claude). The user granted it during this session. `CGPreflightPostEventAccess` and `ListenEventAccess` became true as a side effect. Screen Recording is not granted (window names are absent from window lists).
- The Claude-in-Chrome extension reports "not connected". The extension appears installed in the Default profile but is not attached to this session.
- Chrome 152 runs without `--remote-debugging-port`. Zen 1.21.9b runs with no remote protocol enabled.
- TCC shows the `claude` binary has an Apple Events grant to `com.openai.sky.CUAService` (OpenAI's computer-use service), not to Chrome or other apps. Apple Events to new targets would trigger a consent dialog, so they were avoided.

Format for each entry: mechanism → experiment → observed result → next step.


## Experiments (round 3), all measured by the oracle while the user worked

### E1 — Same-process key routing (routing-lab, corrected event pump)
Mechanism: two AppKit windows in ONE process; post key events with explicit NSEvent.windowNumber via -[NSApp postEvent:atStart:] and via CGEventPostToPid(self); open a sheet; reassign key window.
Result: text always landed at the app's current first-responder, NOT at the stamped window. With the sheet open, keys addressed to window 0 went to the panel. NSApp.keyWindow stayed 0 while the app was inactive, yet edits still occurred. Confirms round 2: **you cannot address a key event to a specific window inside one process.** Consequence: the agent must never share a process with the user's active app.

### E2 — In-process activation attempts (activation-lab, a REGULAR-policy app)
A1 makeKeyAndOrderFront: no front steal. A2 [NSApp activate] (macOS 14 cooperative): inconsistent, brief. A3 activateIgnoringOtherApps:YES: **steals front** (restored). A4 self activateWithOptions:IgnoringOtherApps: brief blip. A5 requestUserAttention: dock bounce only. A6 detached NSAlert: no steal but renders an 8px window at main-display center. A7 standalone NSOpenPanel runModal: no front steal but **renders 868x442 on the MAIN display**. A8 NSSavePanel as a sheet on a parked window: **stays on the hidden display** (2287,508), does not steal. A9/A10 window ordering/unhide: no steal.
Consequence: sheets stay with their parent; standalone panels land on the main display; never call activateIgnoringOtherApps.

### E3 — External activation attempts (activator, from a Prohibited-policy helper)
B1/B2 external NSRunningApplication activateWithOptions: **steal front** (public API; restored). B3 AX kAXFrontmost: err -25204. B4 AXRaise: raised, brief blip. B5 _SLPSSetFrontProcessWithOptions kCPSUserGenerated / B6 kCPSNoWindows / B7 app-active record / B8 yabai focus-flip pair / B9 synthetic mouse records: all rc=0 but none stole the user's frontmost. The yabai focus-flip is a *restore/redirect* primitive, not prevention.
Consequence: the only external calls that change frontmost are the public activate ones, which are on the forbidden list. Background AX never activates.

### E4 — Separate-process instances of native apps
`open -n -gj -a <App>` launches a second, hidden, non-activating instance. Verified TextEdit and Preview: new pid, windows start hidden, frontmost unchanged. This is the fix for E1: give the agent its own process.

### E5 — Native dialog placement on a separate instance (clean, user typing)
Second TextEdit/Preview instance, doc window parked at x=2200. File>Open rendered at [316,139,880,448] on the MAIN display for both apps (standalone panel, root AXWindow id=open-panel). File>Save produced no new top-level window (a sheet, child of the parked doc, stayed hidden). Frontmost never changed. **So separate-process stops focus/keyboard theft, but a standalone Open panel still appears on the user's display.**

### E6 — Panel position persistence / preference seeding
NSOpenPanel saves only NSNavPanelExpandedSizeForOpenMode (SIZE); it does NOT persist origin. No position preference exists to seed. Reopened panels return to main-display center.

### E7 — Watch-and-move relocation (axact watchmove)
Detect the new panel by polling CGWindowList, then AX-move it to the hidden display. Works every time, ax_error=0. Time on the main display from detection to move: ~20-28 ms (one to two frames). The user reported not noticing the flashes.

### E8 — WindowServer-level relocation of a FOREIGN window (foreign-winop, alphacheck)
External SLSMoveWindow: refused (err 1000, no move). External SLSSetWindowAlpha: returns 0 but readback shows alpha unchanged (1.00) — a silent no-op, exactly like the round-2 tag calls. External SLSSetWindowLevel/SLSOrderWindow: no effect. Owner moving its OWN window via SLSMoveWindow: succeeds (positive control). **An external process cannot touch a foreign window at the WindowServer level; only Accessibility works, hence the ~1-24 ms AX latency.**

### E9 — agentdesk end-to-end (the prototype)
`agentdesk` = hidden display + isolated instance (`open -n -gj`) + park + a resident relocator daemon (polls every 2 ms; AX-moves any new main-display window of a registered agent pid onto the hidden display). Demo: launch hidden TextEdit, set text via AX (landed, read back), trigger File>Open (relocated in 1 ms), trigger Save (sheet, stayed hidden). Oracle: front_changes 0, focus_changes 0, pointer_jumps 0, windows_on_main 0.

### E10 — Sustained adversarial load (25 s, user typing in terminal)
Cycled File>Open, Format>Font>Show Fonts, Edit>Find, rapid repeats on the hidden instance. Oracle: keyboard focus owned only by the user's apps (Zen 1504, Ghostty 62439); agent pid never owned focus. No agent window caught on the main display. Relocations 0.8-2.8 ms (avg 1.5 ms). Pointer never moved.

## Verified architecture (native apps)
1. Hidden virtual display (one component).
2. Agent gets its OWN process instance of the app — never shares key-window state with the user's copy. This resolves the same-app requirement by process isolation, not window isolation (which is impossible in one process).
3. Park agent windows on the hidden display with a >=90 px margin.
4. Actuate only via exact-window Accessibility (set value, insert text, AXPress, menu-bar navigation). No synthetic keyboard or pointer events; no activation.
5. A resident relocator pulls any dialog that lands on the main display onto the hidden display within ~1-2 ms. Sheets never appear on main; standalone panels appear for ~1 ms then move.

## Precisely stated remaining gaps
- **Browser (Chrome/Electron):** cannot run a second instance on one profile (ProcessSingleton). The agent must drive Chrome through CDP / the browser extension (DOM events + filechooser interception), not OS input, because Chromium drops background synthetic keys. Not demonstrated this round: the Claude-in-Chrome extension is not connected, and Chrome runs without a remote-debugging port.
- **Canvas/Metal/games:** AX-poor; need pixel clicks that require brief activation. Out of scope.
- **OS/TCC permission dialogs:** rendered by the system on the main display; cannot be hidden or relocated. Occur once per app/permission.
- **Deployment:** the tools currently inherit the terminal's Accessibility grant. A shipped product must be one signed binary granted Accessibility once.

## E11 — Real heavy app: Adobe Illustrator, driven by a subagent through agentdesk
A general-purpose subagent used agentdesk to operate a fresh Illustrator instance (parked on the
corner hidden display) while the user typed in another app. It produced a simple arrow graphic
(`docs/evidence/illustrator-arrow.png`).
- Path used: Illustrator's own script engine via AppleEvents `do javascript` (headless). It made a
  new document, drew the arrow, and exported a PNG. No GUI dialog appeared, so nothing needed moving.
- Oracle during the run: the agent never activated Illustrator, never moved the pointer, and put no
  Illustrator window on the main display. The few front/focus changes were the user's own activity in
  their app; a system notification caused one. `mouse_entered_hidden_display: 0`.
- Honest scope: this proves agentdesk keeps a real, heavy app isolated while it is driven, but the
  script path does not exercise the dialog mover. Dialog relocation (~1-2 ms) is proven separately on
  TextEdit and Preview (E7, E9, E10). Illustrator's canvas is not Accessibility-addressable, so
  freehand drawing needs the script engine, not background GUI clicks.
