# Milestone 5 - Custom-agent execution hardening

Status: plan skeleton. Full spec is written here before code starts.

## Goal

Custom coding agents run as structured executable + args + env, not
interpolated `zsh -ilc` command strings.

## Current state

`CustomCodingAgentClient` builds a shell command by string substitution
(`{prompt}` etc.) and runs `/bin/zsh -ilc <command>`. That inherits the
user's interactive shell environment (slow, flaky, unpredictable) and makes
quoting/injection the user's problem.

## Shape

- Custom agent definition becomes: executable path, argument template list,
  optional env map, working-directory rule, prompt delivery (argv vs stdin
  vs temp file), timeout.
- No login shell by default; explicit opt-in if an agent genuinely needs
  shell evaluation.
- Prompt delivery via stdin or a temp file by default (no argv length or
  quoting hazards).
- Migration: existing saved custom agents (name + command string) are
  parsed into the structured form where possible; anything unparseable is
  flagged in settings with a one-tap "keep legacy shell mode" fallback.
- Validation: test-run button with captured stdout/stderr and exit status.

## Open questions for the spec pass

- Persisted shape change -> new SwiftData schema version + migration.
- Do the OpenCode/Claude Code presets become structured agents
  automatically? (Leaning: yes, they ship as built-in structured defs.)
