# Repository Guidelines

## Project Structure & Module Organization
- `init.lua` — Entry point. Loads `zk`, sets URL handlers, watches this folder for reloads, and wires hotkeys. Requires `wm` and calls `wm.start()`.
- `wm.lua` — Window manager module exporting `wm.start()`, `wm.modal`, `wm.centerCompact()`, `wm.moveToLeftScreen()`, and `wm.moveToRightScreen()`.
- `zk.lua` — Zettelkasten helpers and URL actions (e.g., `zk-capture`, `zk-random`).
- `Spoons/` — Optional Hammerspoon Spoons.
- `zk_config.json` — Configuration for `zk`.
- `.luarc.json` — Lua 5.4 settings and Hammerspoon libs in workspace.

## Build, Test, and Development Commands
- Reload config: use the bound hotkey `cmd+alt+ctrl+r` or Hammerspoon Console: `hs.reload()`.
- Open Console: Hammerspoon menu → Console; inspect logs and run Lua snippets.
- Trigger URL handlers (examples):
  - `open "hammerspoon://zk-random?searchAll=true"`
  - `open "hammerspoon://zk-capture?text=Hello"`

## Coding Style & Naming Conventions
- Language: Lua 5.4; prefer `local` for variables and functions.
- Modules return a table (e.g., `wm`); functions use lowerCamelCase.
- Indentation: match surrounding file (tabs currently). Keep line length reasonable (~100 cols).
- Avoid globals except `hs`. Respect Hammerspoon API idioms and non-blocking UI.

## Testing Guidelines
- No automated tests. Use manual checks:
  - Modal: `cmd+alt+ctrl+x` enters; `c/b/f/v` apply layout and exit; `h/j/k/l` resize and remain in modal; `Esc` exits.
  - Global hotkeys: `cmd+alt+ctrl+c` centers without resizing; `cmd+alt+ctrl+Left/Right` moves to adjacent screen.
  - URL routes: try the `open` examples above and validate expected `zk` behavior.
- Use the Console for quick assertions (e.g., `hs.window.focusedWindow():frame()`).

## Commit & Pull Request Guidelines
- Commits: small, focused, imperative style (e.g., "Extract wm into module"). Reference files and hotkeys touched.
- PRs: include a short summary, before/after notes for behavior, reproduction steps, and any screenshots/recordings if UI changes (alerts/hints).
- Link related issues and call out breaking or binding changes.

## Security & Configuration Tips
- Do not commit personal paths or secrets in `zk_config.json`.
- This repo auto-reloads on `.lua` or `zk_config.json` changes; avoid noisy file writes that could cause rapid reloads.
