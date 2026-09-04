# Anvil - Product Spec

## One-liner

Anvil turns a prompt into a real, signed, sandboxed native macOS app - no
Xcode, no account, no credits. Bring your own models.

## What Anvil is

- A menu-bar macOS app. You type what you want ("a menu bar pomodoro timer"),
  an AI coding agent writes the SwiftUI code, Anvil compiles it, repairs it,
  signs it, sandboxes it, and installs it as a real app you can launch,
  export, or delete.
- Model-agnostic. Local models (Apple Foundation, MLX, Ollama), API-key
  providers (OpenAI, Anthropic, Gemini, any OpenAI-compatible endpoint), and
  real coding agents (Codex CLI, OpenCode, Claude Code, custom) are all
  first-class. The user brings their own keys and tools.
- The moat is the harness, not the model: compile verification, deterministic
  + model-driven repair, sandboxed signed app bundles, export to
  /Applications. Any backend plugs into the same loop.

## What Anvil refuses to be

- No accounts. No sign-in, no profiles, no handles.
- No money. No credits, no credit packs, no checkout, no subscriptions.
- No backend. Anvil talks only to the model providers the user configures.
  There is no Anvil server and no phone-home.
- No app store. The Anvil Store (browse/publish/remix community apps)
  depended on the upstream backend and died with it. Sharing may come back
  later as plain file export/import, never as a hosted service.

## Modes (target state, milestone 3)

- **Tiny App** - the original Anvil loop: one `ContentView.swift`, one
  shot, compile-repair harness. Fast, cheap, great for menu bar utilities.
- **Project** - a real multi-file SwiftPM package (`Sources/App/Views`,
  `Models`, `Services`, ...) that agents can edit across files, with
  user-approved `Package.swift` dependency changes.

## Coding agents (target state, milestone 4)

- **Spark** - local/small-model pipeline. One-shot generation plus
  deterministic repairs. The free/offline tier. Kept as-is.
- **Flame** - big-remote-model pipeline. One good shot plus a few cheap
  repair turns. Transitional; expected to be displaced by real agents.
- **Codex / OpenCode / Claude Code / custom** - real agent CLIs that own
  their build/repair loop. Anvil feeds them the package, validates output,
  and does final build verification. This is where investment goes.

## Non-negotiables inherited from Anvil

- Generated apps are sandboxed and signed; permission planning is automatic.
- Edit flow never destroys a working app: changes stage, build, then swap.
- GPL v3. Attribution to Jade Westover (Jeidoban) and contributors stays.
