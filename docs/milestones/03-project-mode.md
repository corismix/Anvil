# Milestone 3 - Project mode + controlled dependencies

Status: plan skeleton. Full spec is written here before code starts.

## Goal

Raise the ceiling from one `ContentView.swift` to real multi-file apps,
without losing the no-Xcode build/run/export loop that makes Anvil not-a-
terminal.

## Shape

- Generation mode becomes a per-app choice: **Tiny App** (today's
  single-file loop, unchanged) or **Project**.
- Project layout:

  ```text
  Sources/App/
    App.swift        # entry, owned by the agent within rules
    Views/
    Models/
    Services/
    Utilities/
  ```

- Agents may create/edit/delete files under `Sources/` and may *request*
  `Package.swift` changes (add a dependency, bump platforms). Every
  Package.swift change is presented to the user as an allow/reject diff
  before it applies. Rejected changes are fed back to the agent as a
  constraint.
- The harness keeps owning: package scaffolding, protected-file rules,
  final build verification, sandbox/sign/export. Multi-file does not mean
  the agent gets the whole disk.
- Spark/Flame stay Tiny-App-only (one-shot models can't hold a multi-file
  edit loop). Project mode is served by agent backends (Codex, OpenCode,
  custom) - which is why milestone 4 lands right after.

## Open questions for the spec pass

- Dependency allowlist vs free-form requests with review? (Leaning:
  free-form request, human allow/reject, remembered per app.)
- How does the repair loop work multi-file? (Compiler errors map to files;
  agent backends repair themselves; Spark/Flame repair machinery stays
  single-file.)
- Mode migration: can a Tiny App be promoted to a Project? (Leaning: yes,
  one-way, explicit.)
