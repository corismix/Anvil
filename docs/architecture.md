# Anvil Architecture

Snapshot of the codebase as inherited from Ironsmith at a0e29c1, updated as
the fork diverges. `AGENTS.md` remains the operational contributor guide;
this file is the orientation map.

## Shape

- SwiftPM executable package, no Xcode project. macOS 26+, Swift 6.3
  toolchain, Swift 5 language mode, `MainActor` default isolation.
- Menu-bar-first: AppKit `NSStatusItem` + `NSPopover` is the main surface.
  Settings, agent output, and (pre-fork) Store live in separate windows.
- Build: `script/build.sh` (stages `dist/.../Anvil.app`), tests:
  `script/test.sh` (Swift Testing, not XCTest).

## Layers

- `Ironsmith/App` - startup, `IronsmithApplicationController` (wires
  persistence, stores, routing, windows), URL routing, menu.
- `Ironsmith/Core/Models` - domain enums and typealiases to the current
  persistence schema.
- `Ironsmith/Core/Persistence` - SwiftData container, versioned schemas
  (`IronsmithSchemaV1..V7`, one migration plan), repositories, app paths
  (`IronsmithPaths`, data under `~/.ironsmith/`), preferences.
- `Ironsmith/Core/Inference` - provider catalog, credentials (Keychain),
  model discovery/selection, Ollama/local models, `InferenceStore` (shared
  provider/model/preference state), language-model construction.
- `Ironsmith/Core/AgentPipeline` - the harness: generated-package layout
  (`ToolPackageLayout`), prompts, single-file generation runtime, source
  cleanup, deterministic repairs, compile/repair loops, app-bundle
  construction/signing (`ToolAppBundleClient`), icons, agent clients
  (Codex CLI, custom agents), diagnostics.
- `Ironsmith/Features` - `Launch` (Command Line Tools gate, onboarding),
  `ToolLibrary` (popover UI + `ToolLibraryStore`), `Settings`.

## Key patterns

- Views render state and send intent; `@Observable` stores coordinate;
  repositories own SwiftData; small closure-based clients wrap network,
  process, Keychain, filesystem effects. Production wiring via
  `Dependencies.live`; tests inject fake clients.
- Model invocation is stage-based (`codingAgent`, `promptRefinement`,
  `metadata`) routed through `ToolLanguageModelInvoker`.
- Generated tools are SwiftPM packages under `IronsmithPaths.toolsDirectory`;
  all package paths derive from `ToolPackageLayout`.
- Persistence changes require a new immutable schema version + migration
  stage; never mutate a shipped schema.

## Pre-fork backend coupling (removed in milestone 1)

- Supabase auth (Apple OAuth, email/password) via `IronsmithAccountClient`.
- Credits: balance, ledger, credit packs, Stripe checkout sessions via the
  upstream API (`api/v1/...`).
- `Ironsmith` inference provider: OpenAI-compatible proxy on the upstream
  backend, metered in credits (`authMode: .platformCredits`).
- Store: community app browse/publish/remix/Q&A over the same backend.
- Backend config via `Config/.env` / Info.plist keys
  (`IronsmithSupabaseURL`, `IronsmithSupabasePublishableKey`,
  `IronsmithAPIBaseURL`).
