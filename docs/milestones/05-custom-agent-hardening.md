# Milestone 5 - Custom-agent execution hardening

Status: complete. Verified green on main via CI run 33933495793 (https://github.com/corismix/Anvil/actions/runs/33933495793) at commit d8e3665. Temp-file prompt delivery from the plan skeleton was descoped: argv token and stdin cover the delivery modes without a temp-file lifecycle to manage.

## Goal

Custom coding agents run as structured executable + args + env, not
interpolated `zsh -ilc` command strings.

## Current state

`CustomCodingAgentClient` builds a shell command by string substitution
(`{{prompt}}`) and runs `/bin/zsh -ilc <command>`. That inherits the
user's interactive shell environment (slow, flaky, unpredictable) and
makes quoting/injection the user's problem. Native adapter entries
(milestone 4) already launch structured; this milestone brings the same
guarantee to user-defined custom agents.

## Design

### Structured launch definition

`CustomCodingAgent` gains an optional `structuredLaunch`
(`StructuredAgentLaunch`, Codable, additive optional so existing
UserDefaults records decode untouched - no SwiftData involvement; agents
are preferences JSON):

- `executable`: absolute path, or a bare name resolved against PATH plus
  the common install dirs (same lookup the native adapters use).
- `arguments`: ordered argument template. The token `{{prompt}}` as a
  whole argument is replaced by the prompt as a single argv element -
  no quoting, no length hazards beyond exec limits; when the template
  has no token, the prompt goes to stdin.
- `environment`: extra KEY=VALUE entries merged over a minimal inherited
  environment (PATH, HOME, LANG, USER, TMPDIR), not the whole
  interactive-shell environment.
- `timeoutSeconds`: 0 means no timeout; anything else kills the process
  group after the deadline with a clear error.

When `structuredLaunch` is set, `command` and `promptDelivery` are
ignored at run time (kept for reference and downgrade).

### No shell by default

Structured launches never touch a shell. The legacy `zsh -ilc` path
remains only for agents that have not been converted, and the editor
says so.

### Migration

No data migration on launch. The editor offers "Convert to structured
launch" for legacy agents: a conservative parser tokenizes the command
(whitespace + simple single/double quotes) and only succeeds when the
command contains no shell metacharacters (`|`, `;`, `&`, `>`, `<`, `$`,
backtick, glob) other than the `{{prompt}}` placeholder. Parseable
commands prefill the structured fields for review; anything else shows
why it cannot be converted and stays legacy.

### Validation

Existing rules plus: executable required and resolvable (bare name must
be found), argument template must contain `{{prompt}}` at most once, env
keys non-empty and well-formed. The test-run button exercises exactly
the launch the user configured.

## Tests

- Conservative shell parse: clean commands, quoted segments, and
  rejection of pipes/redirects/expansion.
- Argument template resolution: `{{prompt}}` whole-arg replacement,
  stdin fallback when no token, metacharacters in the prompt never
  re-parsed.
- Environment merge: overrides win, minimal base preserved.
- Validation errors for unresolvable executables and bad env entries.
- Timeout enforcement path via a stubbed runner clock (no real process
  spawns in tests).

## Verification

Green CI run on main (`mac.yml`) with the new tests, then this file is
marked complete.
