# Functional interface conventions

This interface is the operational desktop workspace; the voxel farm remains deferred.

- Projects is the default entry. Project rows show a title and human-readable status; creating a project is a separate action.
- Stable navigation selection, compact content-sized actions, consistent input styling and explicit checked/unchecked controls. Primary actions use a single dark-green treatment.
- Conversation separates readable history from a fixed composer. Workflow diagnostics do not dominate the conversation.
- Plan and approval use independently scrollable columns. Goal, tasks and deliverables are on the left; access settings, reviewer selection, save hints and approve/start actions are on the right.
- Unsaved edits still disable approval/start. Access-setting changes require a new approval. These rules are not weakened by the layout change.
- Results leads with produced files and the latest response. Previous attempts, raw event records and usage stay in Activity. No prior records are deleted.
- Active work retains process/elapsed/last-event feedback and a visible Stop action. Idle screens do not show an unnecessary loading area.
- Text stays readable when resizing; system/runtime details are disclosed where relevant rather than repeated across primary screens.

Validation: Godot parser/import check; visual inspection of plan, connections and results; navigation, saved-plan/dirty/reverted approval, report preview and progress presentation smoke checks. No provider calls are needed for this frontend-only change.
