# Milestone 4 - First-class agent adapters

Status: spec complete, implementation in progress.

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

`ToolCodingAgent` gains two cases, `openCode` and `claudeCode`. Existing
raw values (`small_model`, `large_model`, `codex`, `custom`) stay
byte-identical; the new cases are additive and decode-safe.

Each native adapter gets a dedicated client modeled on
`CodexAgentClient`:

- `OpenCodeAgentClient` - runs the user's `opencode` binary directly
  (executable URL + argument array, never a shell string).
- `ClaudeCodeAgentClient` - same treatment for the user's `claude`
  binary, with `--output-format stream-json` transcripts.

Shared adapter surface (not a protocol refactor of the runtime): each
client exposes run-with-request, transcript URL, and a capabilities
value (image input, session resume, permission modes) that the runtime
and UI read through the existing pipeline configuration.

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

- The Coding Agent menu in the composer gains OpenCode and Claude Code
  as first-class entries (next to Codex), separate from the Custom
  submenu.
- Selecting one reveals its options in the generation settings menu:
  model, and per-adapter mode (OpenCode: agent mode; Claude Code:
  permission mode).
- Options persist per app in the committed `.anvil/build-settings.json`
  via new optional fields on `ToolGenerationSettings` (additive,
  decode-safe), so they travel with git history like everything else.

### Session continuation

- Follow-up edits resume the prior agent session for the app when the
  backend supports it: Claude Code via `--resume <session-id>`, OpenCode
  via its session flag.
- The session id is captured from the run's stream-json output and
  stored in `.anvil/agent-session.json` (sidecar, committed), cleared
  when the app is rebuilt from scratch.
- Cold start remains the fallback when no session id is recorded or the
  backend rejects the resume.

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
