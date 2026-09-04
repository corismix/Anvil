# Milestone 2 - Git-backed versions

Status: COMPLETE. Verified by GitHub Actions run 33930498942 on `main`
(macos-26, Xcode 26.6): build + full test suite (496 tests, serial) green
at `029d3e1`. Implementation landed in `367d7be`; follow-ups `55f8153`
(git client inert under swift test) and `029d3e1` (serial test step - real
git spawns starved parallel timing suites on the shared runner).

## Goal

Every generated app is quietly its own git repo. The loop becomes
**prompt -> changes -> diff -> build result**, with undo/restore/compare
built on real history instead of file-copy backups.

## Why first

Cheap, low-risk, and everything after it (project mode, agent adapters)
compounds on having real per-app history.

## Current state (verified against code)

- `ToolVersionBackupClient` (`Core/AgentPipeline/Runtime/`) stages file
  copies into the package metadata dir (`.anvil/`): `pending-` during an
  edit, promoted to `previous-` on success. Exactly ONE previous version
  is kept; restore swaps previous<->current and rebuilds
  (`ToolLibraryStore.restorePreviousVersion`, popover `onRevert`).
- Edit flow (`SingleFileToolGenerationRuntime`): `stageCurrentVersion` ->
  generate -> build -> `promoteStagedVersion`; on failure the current
  source is preserved and the stage is discarded.
- Packages are SwiftPM packages under `AnvilPaths.toolsDirectory`,
  materialized by `ToolPackageMaterializer`.
- Process execution pattern exists: `SwiftPackageProcessClient` shells
  out to `/usr/bin/swift`, `/usr/bin/xattr`, `/usr/bin/codesign` via
  `Process`. Git follows the same pattern.
- No schema change is needed: version history comes from `git log`, not
  SwiftData. Shipped schema versions stay untouched.

## Design

### ToolGitClient (new, `Core/AgentPipeline/Clients/ToolGitClient.swift`)

Struct-of-closures client matching the codebase's dependency style.
Shells out to `/usr/bin/git -C <packageRoot>` (git is present on every
Mac that can run `swift build`, which Anvil already requires).

Operations:
- `ensureRepo(packageRootURL)` - `git init` if no `.git`; idempotent.
  Called lazily at every commit/restore entry point so pre-milestone-2
  tools migrate on first use (initial commit = "Imported existing app").
- `commitAll(packageRootURL, message)` - `git add -A` + commit. Author
  pinned via `-c user.name=Anvil -c user.email=anvil@localhost` so the
  user's git identity is never required or touched. No-op (returns
  false) when the tree is clean.
- `log(packageRootURL, limit)` - parsed `git log` (sha, message, date).
- `diff(packageRootURL, fromSHA, toSHA)` - raw `git diff` output.
- `restore(packageRootURL, sha, paths)` - `git checkout <sha> -- <paths>`
  into the working tree, then a normal `commitAll` ("Restore to
  <short-sha>"). History stays linear; no `reset --hard`, ever.

Git is auxiliary: every call site treats a git failure as non-fatal
(`try?` + `AgentDiagnosticsLog`). Generation never fails because git
failed.

### What gets committed

`.gitignore` written at materialization (and by `ensureRepo` when
missing): `.build/`, `.codex/`, `*.app`, `.anvil/pending-*`,
`.anvil/previous-*`. Everything else - `Package.swift`, `Sources/`,
resources, icon assets in `.anvil/` - is committed, so a restore brings
back source AND icon AND build settings of that version.

### Commit points

- Creation: one commit after the first successful build
  ("Initial version: <prompt excerpt>").
- Edit: one commit at each `promoteStagedVersion` point
  ("Edit: <prompt excerpt>").
- Icon change (`ToolIconEditingClient.install`): "Update app icon".
- Restore: "Restore to <short-sha>" (the restore itself is a commit).

Commit granularity decision: per accepted result, not per pipeline
stage. Stage checkpoints add noise without value; the existing backup
client already covers in-flight protection.

### Backup client after git

`ToolVersionBackupClient` stays for IN-FLIGHT staging only (pending-
files during an edit). The `previous-` file copies become a legacy
fallback: `hasPreviousVersion`/`restorePreviousVersion` consult git
first (>= 2 commits), and fall back to the file copies for tools
created before this milestone that have no git history yet. No
migration of old file backups into git - they age out naturally.

### UI

- Tool details / popover: replace the single "revert" affordance with a
  Versions list (per tool): relative date, commit message (the prompt),
  short sha. Each row: Restore. A "Compare with current" shows the raw
  `git diff` in a monospace sheet (no syntax highlighting in v1).
- Restore flow: checkout version's `ContentView.swift` + build settings
  snapshot -> rebuild -> commit. Same rebuild path as today's revert.

### Settings snapshot

Build settings (`ToolGenerationSettings`) are already serialized by
`ToolVersionBuildSettingsSnapshot`. Keep writing that JSON into
`.anvil/` (committed), so restoring a version restores its settings
too. Reuse the existing Codable with its legacy decode keys.

## Testing

- `ToolGitClient` tests against real git in temp dirs (CI has git):
  init idempotence, commitAll no-op on clean tree, log parsing, diff,
  restore round-trip, .gitignore respected.
- Runtime tests: commit invoked at create/edit/icon/restore points
  (mock client); git failure does not fail generation.
- Legacy fallback: tool without `.git` + `previous-` files still
  restores via the file path.
- Full suite green via GitHub Actions before the milestone is marked
  done.

## Resolved questions (were open in the skeleton)

- Commit granularity: per accepted result. Stage checkpoints rejected.
- Branch-per-edit: rejected for v1 - the backup client's
  stage/promote/discard already gives atomic edit protection; branches
  add user-visible complexity with no payoff at this scale.
- Git binary: shell out to `/usr/bin/git`. No new dependency.
