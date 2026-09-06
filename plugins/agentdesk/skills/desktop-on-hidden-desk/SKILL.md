---
name: desktop-on-hidden-desk
description: Run any macOS desktop app on a hidden desk so it never steals the user's screen, focus, or pointer. Load this before driving a Mac desktop app with computer use — Illustrator, Photoshop, Preview, Keynote, Numbers, Finder, or any app — including whenever the user says "use <app> to ..." or asks you to make something in a desktop app.
---

# Drive desktop apps on a hidden desk (agentdesk)

Whenever you are about to control a macOS desktop app with computer use, do it through
**agentdesk** so the user keeps working undisturbed. The app runs on a hidden display in the
corner of the screen; your work never appears on the user's screen, never moves their pointer,
and never takes their keyboard.

## Workflow

1. **Open the app on the hidden desk.** Call `desk_open({ app: "<App Name>" })`. It returns a
   `pid`, a `window_id`, and a `mode`. If `mode` is `shared_instance`, the app is single-copy
   (Adobe apps): you are sharing the user's one instance, so only proceed if they are not using
   it themselves.
2. **Make sure there is a document/window to work in.** For canvas apps (Photoshop, Illustrator),
   open or create a document first — an app with no open document exposes no canvas window to
   drive. `desk_open({ app, file: "/abs/path" })` opens a file directly with no picker.
3. **Drive the returned `pid` / `window_id` with your normal computer use.** Do NOT bring the app
   to the front and do NOT click to activate it. A canvas app may briefly self-activate for a
   second; that is fine, because its window is on the hidden desk and the user cannot see it.
4. **Prefer the app's own automation when it exists.** Illustrator and Photoshop have a script
   engine (`do javascript`), which is the most reliable way to create art and always runs in the
   background. Use it for precise, multi-step creation; use computer-use clicks for the rest.
5. **Deliver a real artifact.** Export or save the result to a file (for example a PNG or the
   app's native format) and tell the user where it is.
6. **Close the desk when done.** Call `desk_close({ desk_id: <pid> })`. This will NEVER quit an
   app you adopted (the user's own Illustrator/Photoshop); it un-watches it and restores its
   window. It only quits copies agentdesk launched itself.

## Example

User: "Use Illustrator to make me an MTA-style subway poster."

- `desk_open({ app: "Adobe Illustrator 2026" })` → get pid + window on the hidden desk.
- Create a new document, then build the poster — via the Illustrator script engine for the
  layout and type, and computer-use for anything visual you need to check.
- Export a PNG (and optionally save the `.ai`) to the user's Desktop.
- `desk_close({ desk_id: pid })`.
- Tell the user: done, here is the file. Their screen never changed.

## Never

- Never bring the app to the front or move the user's pointer on purpose.
- Never call `desk_close` expecting it to quit the user's own app; it will not, by design.
