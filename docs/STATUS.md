# Implementation and verification status

## Working foundation

- Separate Godot desktop and Python asyncio core; versioned authenticated loopback HTTP/WebSocket protocol; assigned port, one launcher, per-data-folder lock.
- Four discoverable provider adapters: Codex, Antigravity (including WSL), Claude Code, OpenCode. Official sign-in launch, model discovery where supported, manual model IDs and honest unknown capabilities/allowance.
- Sign-in completion automatically refreshes connections. Antigravity does not expose a non-consuming auth-status command, so it is labelled explicitly unverified until a user-requested no-tools verification succeeds. Verification consumes a small provider request, preserves timestamped evidence across refreshes for the same runtime, and clears prior success if a recheck fails. No credential files are inspected. The live Antigravity verification check passed.
- Worker model/role settings and dynamically added/removed/enabled user skills. No preloaded skill claims.
- Real planner discussion; planner output becomes an editable, versioned brief/task plan. No implementation authorization is inferred from discussion.
- Approval snapshots freeze task assignments, connections, models, roles, enabled skills, permissions, context and one correction budget. Unsaved UI changes disable approval/start.
- The editor compares displayed values to the saved plan: initial text-change notifications do not falsely dirty a loaded plan, and reverting an edit restores its clean state. Inline approval hints and a nearby save action explain blocked controls. Assigned workers are excluded from the independent-reviewer choices; None is supported.
- Web permission is frozen per worker. A mixed workflow may grant native web access to Codex while Antigravity/other adapters receive local-file access only. Enabling web without any supported worker is rejected. Existing approvals retain their original scope.
- Sequential task dependencies, optional read-only review, bounded correction and re-review, process cancellation and persistent interrupted state after restart.
- Active attempts expose real process presence, worker/stage, elapsed time, last runtime-event time and last activity. The desktop polls active projects every two seconds and animates an indeterminate activity marker. Quiet output is distinguished from an unavailable core; no inferred percentage or private reasoning is displayed. Planning results are presented as readable briefs rather than raw JSON.
- Persistent attempts, redacted events, usage and output artifacts. A successful exit is not completion. Required outputs must exist and be nonempty. Reviews remain attributed assessments.
- Text/image artifact preview support and explicit source-labelled Markdown memory export. No automatic memory injection.
- Portable Windows application folder produced and startup-tested without relying on the development Python installation.

## Actual live evidence

Codex read a synthetic local source document, wrote a Markdown report and returned structured completion. Antigravity independently read source and report and returned pass. The harness independently checked the report exists, cites the source and contains the expected numeric finding. An earlier restrictive test was correctly blocked when commands were prohibited but Codex required a command to read the file.

These are tiny local-document integration tests, not proof of broad autonomous research accuracy. A separate live Codex native web check accessed the official Godot Windows download page and produced a sourced Markdown note. The activity record contains two runtime web_search events, independently distinguishing actual tool invocation from a final-answer claim. This validates one small public-page lookup, not broad research quality, unrestricted browsing or access to every site. Image-generation/editing and office-document integrations have not been live verified. Native image preview support is not image-generation capability.

## Provisional / deferred

- This is a functional engineering preview, not a completed production release.
- Farm world, avatars and animation are deferred by agreement.
- The first package includes the full portable Godot runtime; optimized export, installer, signing and updates remain work for distribution.
- Claude Code is not installed here. OpenCode account/job execution has not been live verified. Authentication and catalog checks do not establish tool access or entitlement.
- Web research is an explicit Codex-runtime option with a small live lookup verified on this machine; connection/account capabilities are not assumed globally. Other adapters reject that option rather than silently promise it. There is no app-owned browser/scraper.
- Interactive tool permission forwarding, pause/resume, parallel execution, provider installation management, robust provider version negotiation, advanced memory retrieval and automatic capability probes are deferred.
- Workspace validation is not universal OS isolation; each provider's documented permission mechanism has different guarantees. Windows runtime and WSL prerequisites remain external dependencies.
- Completion currently validates explicit paths and structured outcomes, not arbitrary semantic criteria. Independent review is optional and cannot guarantee correctness.
