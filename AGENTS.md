# Repository Guidelines

## Project Structure & Module Organization

- `init.lua` boots the config, loads `zk`, assigns URL handlers, and starts the window manager via `wm.start()`.
- `wm.lua` exports layout helpers (`wm.modal`, `wm.centerCompact()`, `wm.moveToLeftScreen()`, `wm.moveToRightScreen()`).
- `zk.lua` defines Zettelkasten URL actions such as `zk-capture` and `zk-random`; configuration lives in `zk_config.json`.
- `Spoons/` may host optional Hammerspoon Spoons; `.luarc.json` wires Lua 5.4 and Hammerspoon globals for tooling.

## Build, Test, and Development Commands

- Reload after edits with the hotkey `cmd+alt+ctrl+r` or run `hs.reload()` in the Hammerspoon Console.
- Trigger URL handlers from the terminal, e.g. `open "hammerspoon://zk-random?searchAll=true"` or `open "hammerspoon://zk-capture?text=Hello"` to validate `zk` paths.
- Use the Console (Hammerspoon menu → Console) to inspect logs or execute Lua snippets such as `hs.window.focusedWindow():frame()`.

## Coding Style & Naming Conventions

- Lua 5.4; prefer `local` scope and lowerCamelCase function names within modules that return a table.
- Match the existing space-based indentation and keep lines within ~100 characters.
- Respect Hammerspoon idioms—avoid blocking UI calls and keep modules free of global state beyond `hs`.

## Testing Guidelines

- No automated suite; rely on manual checks.
- Enter the modal with `cmd+alt+ctrl+x`; verify `c/b/f/v` apply layouts and exit, `h/j/k/l` resize while staying active, and `Esc` exits.
- Validate global hotkeys: `cmd+alt+ctrl+c` recenters the focused window, arrow bindings move it between screens.
- Confirm URL routes using the `open` commands above and review results in the Console.

## Commit & Pull Request Guidelines

- Write small, imperative commits (e.g., "Extract wm into module") and reference modules or bindings touched.
- Pull requests should summarize behavior changes, note before/after effects, include reproduction steps, and link related issues.
- Add console captures or screenshots when altering alerts or on-screen hints.

## Security & Configuration Tips

- Keep personal paths or secrets out of `zk_config.json`; the repository auto-reloads on `.lua` or config changes, so avoid noisy writes.
- Treat Spoons and external dependencies as optional; document any new requirements in the PR description.
