# Milestone 4 - First-class agent adapters

Status: plan skeleton. Full spec is written here before code starts.

## Goal

Codex, OpenCode, and Claude Code stop being "a saved shell command" and
become native adapters with real UI: model selection, reasoning level,
permissions, session continuation, agent-specific options.

## Current state (from the agent assessment)

- `CodexAgentClient` already runs the bundled Codex CLI properly (prompt
  refinement, `.codex/` JSONL transcripts, final build verification).
- `CustomCodingAgentClient` is a generic `name + command` runner using
  `/bin/zsh -ilc`; OpenCode/Claude Code presets sit on top of it.
- Automatic routing already sends OpenAI models and >600-line jobs to
  Codex.

## Shape

- An `AgentAdapter` protocol behind the existing coding-agent preference
  axis: capabilities (image input, session resume, permission modes),
  launch spec, transcript parsing, option UI descriptors.
- Codex adapter: formalize what exists; expose model + reasoning effort +
  sandbox/approval mode in UI.
- OpenCode adapter: native config (model, agent mode, session continue).
- Claude Code adapter: native config (model, permission mode, resume).
- Custom agents remain for anything else, hardened in milestone 5.
- Session continuation: follow-up edits resume the prior agent session for
  the app instead of cold-starting, when the backend supports it.

## Open questions for the spec pass

- Where do per-adapter options live in the model picker vs settings?
- Which Claude Code / OpenCode versions to target and how to detect them.
