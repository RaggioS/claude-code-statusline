# claude-code-statusline

A single-file, dependency-light status line for [Claude Code](https://claude.com/claude-code). Pure POSIX `sh` + `jq`. Drop it in, point your settings at it, done.

It packs directory, git branch, model, a colored context-window gauge, 5-hour rate-limit usage, and session cost into a responsive 2–3 row layout that adapts to terminal width.

## Preview

```
📂 my-project  ⎇ main
◆ claude-opus-4-8  ■■■□□□□□□□ 28% 56k/200k  ⚡12% ↺143m  💰 $0.42
```

On narrow terminals it collapses gracefully; on very narrow ones it shows only directory + context gauge.

## Features

- Directory + git branch, with branch truncation when space is tight
- Model name
- Context-window gauge: 10-cell bar, percent, `usedk/maxk` tokens, color ramps green → yellow → red as it fills
- 5-hour rate-limit percentage with a reset countdown (`↺NNm`)
- Optional weekly rate-limit percentage + reset countdown, if your plan reports it
- Session cost in USD
- Optional "caveman mode" badge (`🦴 ULTRA`) and "ponytail mode" badge (`🦄 FULL`) — each renders only if the plugin's flag file (`.caveman-active`, `.ponytail-active` in `~/.claude`, or in `$CLAUDE_CONFIG_DIR` if set) exists with a valid mode, otherwise invisible, so it never breaks a shared setup. The ponytail badge is dropped automatically on narrow terminals, when it would overflow the first line or squeeze the git branch out
- Width-aware: reflows between one-line and stacked layouts based on `$COLUMNS`/`tput`
- No external state, no network, no temp files — reads stdin JSON, prints, exits

## Requirements

- Claude Code (status line feature)
- `jq` on `PATH`
- A POSIX shell (`sh`)

## Install

Clone or download `statusline-command.sh` into your Claude Code config, e.g.:

```sh
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/RaggioS/claude-code-statusline/master/statusline-command.sh \
  -o ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then point `~/.claude/settings.json` at it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  }
}
```

Restart Claude Code (or open a new session). The status line updates on each turn.

## How it works

Claude Code pipes a JSON blob to the command on stdin. The script reads it with `jq`, extracts the fields it needs (`workspace.current_dir`, `model.display_name`, `context_window.*`, `cost.total_cost_usd`, `rate_limits.five_hour.*`, `rate_limits.seven_day.*`), measures terminal width, then prints colored segments. No flags, no config file — edit the script directly if you want different colors or segments.

## Customizing

Everything is plain shell. Common tweaks:

- Color codes — standard ANSI escapes inline in the `c_*` segments
- Segments — comment out any `print_*` line you don't want

## License

[MIT](LICENSE) © Raimondo Spatola
