# Milestone 1 - Strip monetization, rebrand to Anvil

## Goal

Anvil has no accounts, no credits, no backend, and no Store - and is named
Anvil everywhere a user can see. GPL attribution is preserved.

## Strategy

Two separately verifiable phases, committed independently:

- **1a: functional strip.** Delete the monetization/backend surface while
  keeping names as-is. Ends with a buildable app that never mentions
  sign-in, credits, or Store.
- **1b: rename.** Mechanical `Ironsmith` -> `Anvil` sweep (types, files,
  directories, bundle id, paths, scripts, strings) plus a `~/.ironsmith` ->
  `~/.anvil` data migration. Done after 1a builds so rename noise never
  hides a functional break.

## 1a cut list

Delete outright:
- `Core/Inference/IronsmithAccount/` (account client, error presentation)
- `Core/Inference/InferenceStore/IronsmithAccount.swift` (session/credit
  store extension)
- `Features/Store/` (whole feature: client, window store/view, import
  client, Q&A, source viewing) and `App/Controllers/
  IronsmithStoreWindowController.swift`
- `Features/Settings/Sheets/IronsmithCredits/`,
  `Sheets/ManageIronsmithAccountSheetView.swift`,
  `Controls/IronsmithAppleSignInButton.swift`,
  `Sheets/AddProvider/IronsmithProviderIntroView.swift`,
  `Sections/SettingsAccountSectionView.swift`
- `Features/ToolLibrary/Popover/ToolLibraryCreditWarning.swift` and
  `ToolLibraryStorePublisher.swift` (publish-to-store flow)
- Store routes in `App/Routing`, store feature flag, store tests.

Surgically remove:
- `ProviderKind.ironsmith` descriptor from `ProviderCatalog`; the
  `.platformCredits` auth mode; ironsmith branches in `RemoteModelClient`,
  `LanguageModelClient`, `AddProviderSheetView`, `ProviderEditorSheetView`,
  `SettingsWindowView`, `ProviderLogoView`, `ModelLogoView`,
  `SettingsProviderCardView`, `ToolAppDetailsEditorSheetView`,
  `ToolLibraryPopoverView`, `ModelPickerSheetView`.
- Credit/session state from `InferenceStore` (`ironsmithSession`,
  `ironsmithAccountSummary`, `ironsmithCreditPacks`, checkout flags) and
  `accountClient` from `InferenceDependencies`.
- Credit gating in `InferenceStore/Generation.swift`
  (`insufficientIronsmithCredits`, credit refresh hooks) and image
  generation provider reconciliation that prefers the ironsmith backend
  (`ImageGeneration.swift`, `ToolImageGenerationClient`).
- Sign-in prompts in onboarding (`IronsmithWelcomeOnboardingSheetView`,
  `WelcomeOnboardingStore`) - onboarding becomes: install CLT, add a
  provider/key, go.
- Supabase package dependency from `Package.swift`/`Package.resolved`;
  backend keys from `Info.plist`, `Config/.env.example`, `script/build.sh`
  plist overrides; OAuth URL scheme from `Info.plist`.

Persistence compatibility:
- `ProviderKind.ironsmith` / `ProviderAuthMode.platformCredits` raw values
  may exist in user databases. Keep the enum cases (deprecated, unreachable
  via UI) so old rows still decode, and delete any persisted `ironsmith`
  provider + its models in `AppDataBootstrapper`/repository bootstrap.
  No schema version bump needed if no stored shape changes.
- `ModelConfig.estimatedToolCredits` stays (harmless persisted metadata,
  now unused by UI).

## 1b rename plan

- Global identifier sweep: `Ironsmith` -> `Anvil`, `ironsmith` -> `anvil`,
  `IRONSMITH` -> `ANVIL` across sources, tests, scripts, plists, docs;
  rename files and directories to match. Exceptions: `LICENSE`,
  `Resources/GPLv3.txt`, copyright/attribution lines, historical references
  in docs, and the upstream repo URL in README attribution.
- Bundle id `com.jeidoban.Ironsmith` -> `com.corismix.anvil`; OAuth callback
  scheme is deleted in 1a so no scheme rename is needed.
- `IronsmithPaths` -> `AnvilPaths`, data root `~/.ironsmith` -> `~/.anvil`.
  Startup migration: if `~/.anvil` is absent and `~/.ironsmith` exists,
  move it (rename, not copy) before SwiftData opens. Log the move.
- `NSHumanReadableCopyright` keeps Jade Westover; add corismix /
  Anvil contributors line where a second line is natural (README, About).
- Repo rename corismix/Ironsmith -> corismix/Anvil happens on GitHub after
  push (corismix action).

## Status

- 1a code strip: COMPLETE. Verified by GitHub Actions run 33925047708
  (macos-26, Xcode 26.6): `script/build.sh` + `script/test.sh` green on
  `68bc505` - 490 tests pass. Test suite updated in the same pass: account/credit/store
  tests deleted, provider tests repointed to OpenAI/Ollama equivalents.
  Full-repo sweep shows zero references to deleted symbols; remaining
  `ironsmith` mentions are intentional decode-compat keeps
  (`ProviderKind.ironsmith`, `ProviderAuthMode.platformCredits`, persisted
  `estimatedToolCredits`, schema migrations V4-V7).
- CI: `.github/workflows/mac.yml` builds (debug, ad hoc signed) and tests
  every push/PR on the `macos-26` runner. Upstream `ci.yml` and
  `release.yml` deleted (release flow depended on removed backend flags and
  Developer ID certs; Anvil release packaging is future work).
- 1b rename: COMPLETE. Verified by GitHub Actions run 33926963560
  (macos-26, Xcode 26.6): build + full test suite green on `bd84b83`.
  Shipped in `c9a543d` (global content sweep, 33 file/dir renames,
  ~/.ironsmith -> ~/.anvil data migration with sidecar handling, README
  rewrite, About/Info.plist attribution kept), with decode-compat fixups in
  `317f678` (ProviderKind.ironsmith restored in 4 files, Keychain service
  name kept, legacy .ironsmith package-metadata fallback) and `bd84b83`
  (Codex configuration identifiers -> anvil_ prefix).
- MILESTONE 1 COMPLETE. Remaining follow-ups owned outside this milestone:
  GitHub repo rename corismix/Ironsmith -> corismix/Anvil (user action on
  GitHub), Package.resolved regenerates on first Mac build, Mac runtime
  smoke check via Aside brief.

## Verification

- Done via GitHub Actions (`.github/workflows/mac.yml`): 1a green on run
  33925047708 (`68bc505`), 1b green on run 33926963560 (`bd84b83`). Mac
  runtime smoke (Aside) covers what CI cannot see: app launch, onboarding
  without sign-in, settings without account section, generation E2E,
  migrated ~/.anvil data loads.
- Manual smoke (Aside): app launches, popover opens, onboarding shows no
  sign-in, settings has no account section, generation with an API-key or
  local model works end to end.
