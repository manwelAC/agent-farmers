# Farm scene — first playable pass

The default Farm screen is an original procedural 3D diorama in Godot. Box meshes,
flat materials, orthographic projection and directional shadows establish the
voxel direction without external image assets.

Click the planning table to open Projects, or either farmer to open Workers.
Two illustrative farmers stroll while idle and show a simple activity animation
when the core reports busy. They do not yet represent particular saved workers;
the UI explicitly labels this limitation. No task is started by clicking scenery.
Existing approval, persistence and provider controls remain in the Python core.

This pass includes a barn, beds, paths, fences, trees and pond. It is not the final
game interface: assignment-specific actors, pathfinding/collision avoidance,
state-specific work/review/blocked animations, camera controls and in-world
project selection remain to be implemented.

The shared application theme now covers navigation, forms, conversations,
approval tabs, outputs, account settings, popups and scrollbars. Parchment panels,
soil-colored borders, square raised buttons and green selection states sit over
the farm backdrop. Everyday text uses a readable regular font. Existing screen
names and permission controls retain their meaning; farm metaphors do not replace
important actions. All screens still use the existing functional navigation;
this is not yet an entirely in-world interaction system.

Verification: Godot import/parse; launcher headless UI smoke including Farm;
actual rendered screenshot inspected at work/farm-preview.png. No agent requests
or user project execution were needed for these checks.
