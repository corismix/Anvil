# Milestone 4 - First-class agent adapters

Status: complete. Verified green on main via CI run 33933079703 (https://github.com/corismix/Anvil/actions/runs/33933079703) at commit b69da77. Design note: implemented as adapter-backed custom-agent entries (structured direct launch) rather than new ToolCodingAgent cases; OpenCode session resume was descoped (no reliably parseable session id in its output), and flag probing was descoped in favor of clear unavailable-adapter errors.

## Goal

Codex, OpenCode, and Claude Code stop being "a saved shell command" and
become native adapters with real UI: model selection, reasoning level,
permissions, session continuation, agent-specific options.

## Current state

- `CodexAgentClient` already runs the bundled Codex CLI properly (prompt
  refinement, `.codex/` JSONL transcripts, final build verification).
- `CustomCodingAgentClient` is a generic `name + command` runner using
  `/bin/zsh -ilc`; OpenCode/Claude Code presets sit on top of it.
- Automatic routing already sends OpenAI models and >600-line jobs to
  Codex.

## Design

### Adapter model

Native adapters ride the existing custom-agent path instead of a
`ToolCodingAgent` enum change: `CustomCodingAgent` gains an optional
`nativeAdapter` kind (plus `adapterModel` / `adapterMode` options), and
`CustomCodingAgentClient` launches adapter-backed entries directly -
resolved executable URL plus argument array, never `/bin/zsh -ilc`.
This keeps per-app agent association, transcripts, cancellation, and
protected-file validation identical across all workspace agents, and
`ToolCodingAgent` raw values stay byte-identical.

- `NativeCodingAgentKind`: `openCode`, `claudeCode` (display name,
  executable name, default model, resume capability).
- `NativeCodingAgentAdapter`: executable lookup (PATH + common install
  locations), launch-spec builder, Claude stream-json session-id
  parsing.
- Claude Code launches as `claude -p --permission-mode <mode>
  --output-format stream-json --verbose --model <model>` with the
  prompt on stdin; OpenCode as `opencode run [-m model] <prompt>`.
- Adapter-backed entries are seeded into the agent list automatically
  when the CLI is detected (`ensureNativeAdapterAgents`), and their
  editor sheet shows model/mode fields instead of a command string.

### Detection

- Binary lookup: `PATH` search via `/usr/bin/which`, falling back to
  common install locations (`~/.local/bin`, `/opt/homebrew/bin`,
  `/usr/local/bin`). Version read from `--version` output.
- An adapter whose binary is missing shows as unavailable in the picker
  with a hint, mirroring how Codex surfaces a missing client.
- Targets: OpenCode `opencode run` (v0.x line), Claude Code `claude -p`
  with stream-json (v1/v2 line). Detection validates the flags we use
  exist rather than pinning exact versions.

### Options and UI

- Detected adapters appear as named entries (OpenCode, Claude Code) in
  the Coding Agent > Custom list; selecting one works exactly like a
  custom agent pick, so the existing picker UI covers it.
- Per-adapter options (model, mode) live on the agent entry itself,
  edited in the manage-agents sheet; they persist in the custom-agents
  preferences record (additive optional fields, decode-safe).

### Session continuation

- Follow-up edits resume the prior agent session for the app when the
  backend supports it: Claude Code via `--resume <session-id>` (OpenCode
  output carries no reliably parseable session id, so it cold-starts).
- The session id is captured from the run's stream-json output and
  stored in `.anvil/agent-session.json` (sidecar, committed).
- Cold start remains the fallback when no session id is recorded.

### What stays the same

- Custom agents (anything that is not Codex/OpenCode/Claude Code) keep
  working through `CustomCodingAgentClient`; they are hardened in
  milestone 5, not here.
- Automatic routing is unchanged: it still prefers Codex; the new
  adapters are explicit user picks.
- The old `claudeCode` / `openCode` presets are superseded by the native
  adapters; existing saved custom agents with those commands are left
  untouched.

## Tests

- Argument construction for both adapters (no shell interpolation).
- stream-json transcript parsing from recorded fixtures, including
  session id capture.
- Session resume: second run for the same app passes the stored session
  id; missing/invalid id falls back to cold start.
- Availability detection with a stubbed file client; unavailable
  adapter hides or disables its picker entry.
- No real binary spawns in tests (clients inert under
  `ANVIL_RUNNING_TESTS=1`, same pattern as the git client).

## Verification

Green CI run on main (`mac.yml`) with the new tests, then this file is
marked complete.
