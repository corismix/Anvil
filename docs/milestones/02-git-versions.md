# Milestone 2 - Git-backed versions

Status: plan skeleton. Full spec is written here before code starts.

## Goal

Every generated app is quietly its own git repo. The loop becomes
**prompt -> changes -> diff -> build result**, with undo/restore/compare
built on real history instead of file-copy backups.

## Why first

Cheap, low-risk, and everything after it (project mode, agent adapters)
compounds on having real per-app history.

## Shape (to be validated against the code at execution)

- Generated tools already live as SwiftPM packages under
  `IronsmithPaths.toolsDirectory` (post-rename: `AnvilPaths`). Each package
  root gets `git init` on creation; the generation pipeline commits at each
  successful stage boundary (generated -> repaired -> built).
- `ToolVersionBackupClient` (in `Core/AgentPipeline/Runtime/`) currently
  stages/restores file copies to protect the edit flow. Git becomes the
  source of truth for history; the backup client either becomes a thin
  wrapper over git (stash/branch for in-flight protection) or stays for
  in-flight staging only, with git owning committed history.
- UI: per-tool version list (prompt, timestamp, build result), restore to
  version, diff between versions. Diffs render from `git diff`, no new
  snapshot format.
- `.gitignore` per tool package: `.build/`, `.codex/`, derived bundles.

## Open questions for the spec pass

- Commit granularity: one commit per successful generation/edit, or per
  pipeline stage? (Leaning: per accepted result, stage checkpoints as
  fixup commits squashed away.)
- Does the edit flow's "preserve original until new build passes" become a
  branch-per-edit with merge-on-success? (Leaning: yes.)
- Git binary: shell out to `/usr/bin/git` (present on every macOS with
  CLT, which the app already requires) vs SwiftGit2 dependency.
  Leaning: shell out, no new dependency.
