# Initial architecture decisions

Status: implementation baseline, 2026-11-04. Windows is the first validated target; cross-platform support is not yet promised.

- Godot/GDScript handles presentation. Python owns workflows, connections, authorization and persistence. No provider subprocesses or business rules in the frontend.
- One launcher owns both processes. The core binds an OS-assigned loopback port, generates a per-launch token, and serves a versioned HTTP/JSON interface plus authenticated WebSocket events. No fixed service ports, Docker or manually launched server.
- SQLite stores versioned plans, exact approval snapshots, task attempts and events. Project files are separate from operational data. Explicit memory export writes Markdown to a separate Agent Farmers Vault.
- Workers reference a connection and a model, role and user-created skills. Runtime tools belong to the provider. Signed-in state and model catalogs do not prove tool capability.
- Each plan task has a worker, dependencies, desired output paths and acceptance instructions. Approval freezes the brief, task graph, permissions and worker configurations. Scope changes require new approval.
- One task runs at a time. An optional assigned read-only reviewer may review output; one correction and re-review are allowed. No autonomous endless debate or silent retry after restart.
- CLI adapters normalize output and preserve redacted raw diagnostics. A successful exit is separate from delivery and acceptance. Unreadable final responses, unavailable tools and permission refusals are visible blockers.
- Workspace validation and runtime permission modes constrain execution. The app cannot turn a runtime's coarse permissions into a universal OS security boundary. No unrestricted execution flags, undocumented consumer endpoints or credential extraction.
- Initial supported runtime candidates: Codex, Antigravity, Claude Code, OpenCode. Actual verification is reported per connection and capability. Tools are not presumed available merely because a model supports them elsewhere.
- Operational memory stays in SQLite. Vault notes are explicit, source-labelled exports; they are not silently injected into future tasks.
- Packaging and readable long-form controls are validation gates. Versions are pinned from installed/retrieved official distributions. No reuse of the previous Qt packaging.

## Deferred

Voxel farm, avatars, parallel scheduling, automatic updates, provider-independent tool hosting, vector memory search, team/cloud sync and generalized interactive CLI terminal emulation. Unsupported interactive permission requests must stop with a clear blocker.
