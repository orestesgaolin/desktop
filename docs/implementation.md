# Implementation notes

This document describes the implementation of the macOS presentation built with
[flutter_deck](https://pub.dev/packages/flutter_deck), combining native
multi-window demos, a live 3D landscape, an interactive design editor, and a
gallery of GPU rendering demos built directly on
[Flutter GPU](https://github.com/flutter/flutter/blob/master/engine/src/flutter/docs/impeller/Flutter-GPU.md)
(`package:flutter_gpu`), Flutter's low-level Impeller graphics API.
The hand-written GPU demos render their viewports with render passes and
`impellerc`-compiled GLSL, without `Canvas`, `CustomPaint`, or
`FragmentProgram`.

## Presentation architecture

`lib/src/deck/` contains a 29-slide `flutter_deck` presentation. Arrow keys
move through the deck and `⌘.` opens the slide drawer.

Presentation metadata is configured once in `lib/src/deck/config.dart`.
Its title, author, date, and place are combined into the footer shared by
all numbered slides.

| # | Slide |
| --- | --- |
| 1–4 | Opening question, optional live poll, desktop screenshot, and the 2020 talk |
| 5–7 | Desktop timeline, the gap after stable, and Canonical's Ubuntu installer |
| 8–13 | Window types, the API, shared widget tree, browser, panels, and floating window demos |
| 14–17 | Transition flyover, Flutter GPU shaders, and flutter_scene |
| 18–19 | UI editor introduction and demo |
| 20–25 | Desktop apps, engine experiments, and current platform issues |
| 26–27 | Visible's desktop development workflows |
| **28** | **Sources** — the public reference page |
| **29** | **Q&A close** — the callback to the opening desktop screenshot |

## Live poll

The poll slide fetches results as soon as it opens and refreshes them every
two seconds while it remains visible. Bars and vote totals animate between
responses. Pass the endpoint at build or run time:

```sh
fvm flutter run -d macos \
  --dart-define=POLL_RESULTS_URL=https://example.com/poll-results.json \
  --dart-define=POLL_VOTE_URL=https://roszkowski.dev/vote \
  --dart-define=POLL_VOTE_LABEL=roszkowski.dev/vote
```

When `POLL_VOTE_URL` is set, the slide shows a continuously moving “VOTE NOW”
strip along its lower edge and keeps it visible on slide 3. The vote URL and
label default to `https://roszkowski.dev/vote` and `roszkowski.dev/vote`.
Slide 2 starts with a large QR code for 12 seconds, then moves it beside the
live results. Override `POLL_VOTE_LABEL` to change the audience-readable text,
or set `POLL_VOTE_URL` to an empty value to hide the strip.

The endpoint must return JSON in this shape:

```json
{
  "title": "Which desktop platform are you targeting?",
  "options": [
    {"label": "macOS", "votes": 34},
    {"label": "Windows", "votes": 28},
    {"label": "Linux", "votes": 21}
  ]
}
```

`question` may replace `title`; `results` or `answers` may replace `options`;
and each option may use `count` or `value` instead of `votes`. Set
`POLL_RESULTS_INTERVAL_SECONDS` with another `--dart-define` to change the
refresh interval. With no URL, the slide uses a simulated feed for rehearsal.
Set `showAudiencePoll` in `lib/src/deck/slides.dart` to `false` to leave it
out of a rehearsal or the final talk.

For Google Forms, link the form to a Google Sheet and publish a small Apps
Script web app that aggregates the answer column. A minimal handler is:

```js
function doGet() {
  const sheet = SpreadsheetApp.getActive().getSheetByName('Form Responses 1');
  const lastRow = sheet.getLastRow();
  const values = lastRow < 2 ? [] : sheet.getRange(2, 2, lastRow - 1, 1)
      .getValues().flat().filter(String); // Change column 2 for your question.
  const counts = values.reduce((all, answer) => {
    all[answer] = (all[answer] || 0) + 1;
    return all;
  }, {});
  return ContentService.createTextOutput(JSON.stringify({
    title: 'Which desktop platform are you targeting?',
    options: Object.entries(counts).map(([label, votes]) => ({label, votes})),
  })).setMimeType(ContentService.MimeType.JSON);
}
```

Deploy it as a web app with read-only public access to the result endpoint.
Keep secrets and Google credentials server-side; do not pass them through
`--dart-define`.

## 3D flyover

Slide 15 looks like every other slide in the deck. It is not: the paper is
a wash over a live `flutter_scene` view parked head-on against a monolith
standing in a forest clearing, framed so the panel covers the viewport
exactly. Pressing → lifts the wash and flies the camera out of the
clearing for twenty seconds, banking over the treeline, low across a lake,
up onto a plateau and square against a second panel in front of a
glass-and-concrete pavilion. The wash returns as it settles, and the deck
advances itself to the next story beat with no second keypress. Pressing →
during the flight cuts it short and advances directly.

The landscape is generated, not authored: a `FastNoiseLite` heightfield
with lakes carved into it, ~2 600 instanced spruces and birches in two
draw calls, 700 instanced boulders, a pavilion assembled from primitives
with the Flutter & Friends logo on a rooftop sign, and a flock of
simplified Dashes circling over the clearing, the lake and the pavilion
(`lib/src/flyover/world.dart`). Each bird is the same six instanced meshes
— body, belly, beak, tail, wings, eyes — so the whole flock is six draw
calls however many there are, and the per-frame work is rewriting their
transforms.

The camera runs a Catmull-Rom spline re-parametrised by arc length, so it
holds a steady speed regardless of waypoint spacing, banks into its own
turns, opens the lens through the cruise, and carries a slow hand-flown
wander that fades to nothing at both docks so the panels still frame
exactly (`lib/src/flyover/camera_path.dart`). The bank is baked once from
the path's turn *rate* rather than derived per frame from the curvature of
the sampled positions — that second difference is mostly sampling noise,
and it reads as a shiver. Measured at a locked **120 fps** through the
whole flight on a ProMotion panel, in a debug build, with cascaded
shadows, GTAO, screen-space reflections, fog and bloom on.

Two traps worth knowing, both of which cost a debugging round here:

- Assigning `scene.environmentSettings` applies the *whole* snapshot,
  including its own (null) `skybox`, `skyEnvironment` and `sunLight` — so
  setting the sky on the scene before it silently wipes it out. Pass the
  sky bindings **inside** `EnvironmentSettings`.
- `SceneView(warmUp: true)` keeps the view behind a reveal that never
  fires in this setup, leaving the slide blank.

`GPU_FLYOVER_CAPTURE=1` drops the dithered screen-space effects, whose
noise inflates a captured frame past what screenshot tooling carries.

## Flutter GPU demo gallery

| Demo | What it shows |
| --- | --- |
| Hello Triangle | Minimal pipeline: one vertex buffer, two shaders, animated on the GPU |
| Ceramic Cube | Indexed draw, depth buffer, back-face culling, 4x MSAA resolve |
| Galaxy Particles | 40k instanced billboards (`VertexStepMode.instance`), additive blending |
| SDF Raymarch | Fullscreen raymarcher: smooth-min morphs, soft shadows, AO, fog |
| Nordic Sea | Raymarched wave heightfield with fresnel, sun glitter, foam |
| Metaballs | Analytic 2D iso-surface with gradient shading (one ball follows the pointer) |
| Plasma | Domain-warped oldschool plasma with cosine palettes |
| Mandelbrot | Smooth escape-time fractal; drag to pan, scroll for anchored zoom |
| Widget Stage | Real, live Flutter widgets captured as GPU textures and spun on a 3D carousel |
| Scene: Still Life | [flutter_scene](https://pub.dev/packages/flutter_scene): scene graph, soft PBR + IBL, shadow-casting sun, orbit camera |
| Scene: Animated Fox | flutter_scene glTF asset pipeline + blended skeletal animation (Khronos sample Fox) |
| Live Editor | ShaderToy-style: type GLSL, ⌘⏎ compiles it at runtime and hot-swaps the pipeline |

Toolbar: play/pause, time scale, and render-scale (50/75/100 % of native
resolution). The stats readout shows live fps and the surface size in
physical pixels.

The frame loop is vsync-driven (a `Ticker` per frame), so the app runs at
whatever the display delivers — verified at **120 fps** on a MacBook Pro
ProMotion panel (all demos, including the raymarchers at full 2x retina)
and 60 fps on a 60 Hz external display. Launch with
`GPU_PLAYGROUND_SCREEN=fast` to open the window on the highest-refresh screen
automatically, or drag it there. `GPU_PLAYGROUND_PROMOTION=1` remains as a
legacy alias.

## Design Canvas

The Design Canvas is a serializable desktop graphics-editor demo rather than
a static slide. Its current interaction model was refined through native mouse
and trackpad testing and is covered by document, shader-compilation, and widget
workflow tests in `test/demos/`.

### Current interaction model

| Area | Behavior |
| --- | --- |
| Selection | Pointer-down selects immediately and can start a drag. Single-click selects text; double-click edits it. Nested frames are directly selectable. |
| Transforms | Eight resize handles, a top-center rotation handle, Shift-resize for proportional scaling, Shift-rotation for 45-degree snapping, and screen-aligned dragging for rotated objects. |
| Hierarchy | Layers can be nested, reordered between siblings, or detached at the root. Moving or rotating a container updates its descendants. |
| Mouse | Primary drag moves objects. Space-primary drag and middle-button drag pan the viewport. |
| Trackpad | Two-finger gestures pan and pinch gestures zoom. Trackpad gestures never select, move, resize, rotate, or modify component slots. |
| Zoom | Pointer-centered modifier-wheel zoom, trackpad pinch, fit canvas, focus selection, and one coordinate model for objects, handles, grid, and guides. |
| Snapping | Movement snaps object edges and centers to the parent and siblings, then falls back to the document grid. Tolerance remains stable in screen pixels. |
| Layers | Recursive tree, drag-to-reparent, before/after drop zones, context menus, inline rename, and sibling front/back ordering. |
| Components | Separate definitions and instances, component-edit mode, positioned slots, layer-to-slot assignment, component references, and slot deletion. |
| Content | Rectangles, ellipses, text, raster images, SVG images, lines, components, filters, radius, and frame or artboard shaders. |
| History | Up to 1,000 complete serialized states, branching undo/redo, preserved viewport and selection, full-history save/import, and autoplay. |
| Shaders | Custom runtime compilation, previous-result retention while compiling, last-good fallback, and `Frame only` or `Frame + children` scope. |

The implementation follows several rules that should remain explicit as it
grows:

- View state (zoom, pan, selection, hover and edit modes) is separate from the
  serialized document state.
- Mouse object manipulation and trackpad viewport navigation are different
  input classes and must not compete for the same gesture.
- Selection is separate from text, rename and component editing.
- A continuous move, resize, rotation or slot edit creates one history state
  when the gesture finishes.
- Asynchronous rendering keeps the previous valid visual result until a new
  shader or asset is ready.

### Main architectural constraint

Hierarchy is currently semantic while geometry remains in canvas coordinates.
Children store absolute position and rotation. Parent movement and rotation
therefore update every descendant explicitly; ordinary parent resize does not
scale children, while component slots use a separate relayout path. Deleting a
container promotes its children to the deleted container's parent.

This makes one `parentId` relationship behave differently for move, rotate,
resize and delete, and it was the common cause behind several interaction
fixes. Before extending nested layout further, the editor should distinguish:

- **Group** — a transform-only collection whose children share its transform.
- **Frame** — a bounded container with background, clipping and layout rules.
- **Component definition** — a reusable editable layer subtree.
- **Component instance** — a reference with explicit overrides.
- **Slot** — a typed placement rule for layer or component content.

Children should eventually store parent-local transforms. Rendering, hit
testing, handles, snapping, reparenting and serialization can then use composed
matrices instead of per-operation descendant patches.

### Remaining core UX work

The most important missing editor behaviors are:

1. **Consistent hierarchy transforms.** Define parent resize, rotated nesting,
   reparenting, deletion and clip-content behavior using local transforms.
2. **Multi-selection.** Add Shift-click, marquee selection, Command-A, shared
   transform bounds, group/ungroup, alignment, distribution and bulk styling.
3. **Deep and overlapping selection.** Add click cycling, select-through,
   enter-container and Escape-to-parent behavior. Locked layers should not
   participate in canvas hit testing.
4. **Layer management.** Add visibility, locking, expand/collapse, search,
   reveal selection, persistent expansion state and drag auto-scroll.
5. **Precise transforms.** Make X, Y, width, height and rotation editable. Add
   arrow-key nudging, larger Shift nudges, aspect lock, resize from center,
   flip, reset rotation and a temporary snapping override.
6. **Transform-aware snapping.** Support rotated bounds, resize snapping,
   equal-spacing guides, distance labels, explicit snapping preferences and
   clear visual indication of the active anchors.
7. **Gesture transactions.** Capture gesture-start state and restore it on
   cancellation rather than leaving a partially changed object outside
   history.
8. **Real tool modes.** The Move control is currently only a visual affordance,
   while shape tools insert fixed-size objects. Add click-drag creation, active
   tool cursors and Escape-to-Move behavior.
9. **Editor/deck focus ownership.** While the canvas is active, editor keyboard
   commands should win over slide navigation. Escape can return focus to the
   presentation.
10. **Document safety.** Add dirty-state feedback, Save As, autosave/recovery,
    recent files and confirmation before replacing unsaved work.

### Components and layout

The component proof of concept still needs normal component-authoring UX:

- Create a component from a selection and edit a definition-owned layer tree.
- Update all instances when the master changes.
- Support text, image, color, visibility and slot overrides, with Reset and
  Detach actions.
- Rename, duplicate and order slots; define whether each slot accepts one item,
  multiple items, arbitrary layers or selected component types.
- Show empty, occupied and incompatible slot states clearly.
- Add pin, fill, hug, fixed, min/max, padding, gap and auto-layout rules.

Frames also need explicit `Clip content` behavior. A child currently belongs to
a frame in the Layers tree but may still paint outside it.

### Content and style backlog

- Text: alignment, line height, letter spacing, vertical alignment,
  auto-width/auto-height/fixed-frame modes, truncation and overflow warnings.
- Images: replace, crop, focal point, original-size restore, fit/fill controls,
  opacity and loading/error states.
- Shapes: stroke, opacity, shadows, gradients and independent corner radii.
- Lines: endpoint handles, arrowheads, dash patterns and joins, followed later
  by Bezier paths.
- SVG: preserve-vector export first; editable paths, boolean operations and
  reusable icon symbols later.
- Styles: named text, fill, effect and shader styles for maintaining larger UI
  documents.

### Screens, navigation and output

The current phone design is one composition on one canvas. A screen-design and
prototype workflow would additionally need:

- Multiple pages or artboards, screen thumbnails, device presets and safe areas.
- Links, tap interactions, transitions, a start screen, back navigation and a
  prototype preview.
- PNG, SVG and PDF export, selected-artboard export, transparent backgrounds,
  scale presets and system-clipboard interchange.
- A direct way to insert or update a selected artboard as a presentation slide.
- Responsive panels and toolbar overflow for narrower presentation windows.

### Shader and history follow-ups

`Frame + children` currently applies the shader independently to every
descendant, so UV coordinates restart at each layer. A true subtree effect
should flatten the visual subtree to one texture and run the shader once.
Future shader UX should also expose uniforms, ordering relative to filters,
preview bypass, source error locations, debounce/cancellation and cached
thumbnails.

Autoplay currently uses the same snapshot sequence as edit history. A more
complete version should separate presentation playback from undo, then add a
scrubber, pause/resume, speed, state labels, timestamps and return-to-current.
Embedded assets should also be stored once by content hash rather than repeated
inside every full-document history snapshot.

### Recommended sequence

1. Define group/frame/component semantics and migrate to parent-local transforms.
2. Establish canvas focus, keyboard ownership and arrow-key nudging.
3. Add multi-selection, marquee, lock/hide and deep-selection rules.
4. Add numeric transforms, transform-aware snapping and clipping.
5. Implement real drawing tools and complete document safety and export.
6. Build master components, instance overrides and responsive layout.
7. Add multiple screens/artboards and prototype navigation.
8. Implement composited subtree shaders and a separate playback timeline.

This order avoids adding more per-frame and per-component exceptions to the
current flat world-coordinate model.

## Runtime shader editing

The hand-written Flutter GPU demos compile their GLSL at runtime. Each demo
declares its sources (`shaders/*.vert|frag`, shipped as plain-text assets); on
first open they are compiled by the SDK's `impellerc` and loaded with
`gpu.ShaderLibrary.fromBytes`. The `{ }` toolbar button opens a shader editor
for the current demo — one tab per stage — and ⌘⏎ recompiles and hot-swaps its
pipelines while it runs.
Compile errors show inline with `name:line` positions and the previous
pipeline keeps rendering. On Widget Stage the side panel has
Widgets / GLSL tabs.

## Development requirements

- Flutter **master** channel (Flutter GPU is not available on stable).
  The repo is pinned via `.fvmrc` for [fvm](https://fvm.app) users.
- Flutter's experimental desktop windowing feature enabled once for the SDK:
  `fvm flutter config --enable-windowing`. The windowed browser on slide 11 uses the
  first-party `WindowController` / `Window` API, so detached tabs share the
  same widget tree and application state as the deck.
- The `impellerc` binary from a Flutter SDK. It is auto-discovered from
  the `flutter` on PATH or FVM installs; set `$IMPELLERC` to override.
- macOS with Impeller (default on master; also forced via
  `FLTEnableImpeller` in `macos/Runner/Info.plist`).

## Run

```sh
fvm use master          # or make sure `flutter` is the master channel
fvm flutter run -d macos
```

The app opens on slide 1 of the deck. The gallery described below is slide 16;
everything in it works exactly as it did standalone.

## Rendering and project structure

- `shaders/*.vert|frag` — Impeller-dialect GLSL, bundled as plain text
  assets and compiled at runtime (`lib/src/live_compiler.dart` →
  `impellerc` → `ShaderLibrary.fromBytes`).
- `lib/src/demos/demo.dart` — each demo declares `ShaderDoc`s (name,
  stage, source); `ensureReady`/`recompile` compile them into a bundle
  and rebuild pipelines. `lib/src/shader_editor.dart` is the editor UI.
- `lib/src/gpu_kit.dart` — a reflection-based `UniformWriter` (uniform
  member offsets come from shader reflection, so no hardcoded std140
  layout math and user edits to uniform blocks bind leniently).
- `lib/src/surface_view.dart` — hosts a `GpuImageSurface`: each Ticker
  tick acquires a frame texture, lets the active demo encode its render
  pass(es), presents, and paints `surface.currentImage`.
- `lib/src/deck/` — the presentation: `config.dart` (title, author, date,
  place), `deck_app.dart` (app + theme),
  `slides.dart` (the ordered slide list), the numbered files in `slides/`
  (one file per slide), and `page.dart` (the
  shared slide layout and type ramp).
- `lib/src/flyover/` — `world.dart` (the procedural landscape, built once
  at launch so slide 15 has nothing left to do), `camera_path.dart` (the
  flight), `flyover_view.dart` (the widget, the wash, and the step wiring).
- `lib/src/gallery.dart` — the demo gallery shell, hosted by slide 16.
- `lib/src/demos/` — one class per demo. 3D demos build their own
  pipelines, vertex/index buffers, and depth/MSAA attachments; the
  fullscreen shader-art demos share a 3-vertex fullscreen-triangle
  pipeline and a common `FragInfo` uniform contract (resolution, pointer,
  time, 4 generic params).

## Widget Stage

Real Material widgets (switches, a button, an animated progress bar, a
ticking clock) live in a side panel. One card per frame is snapshotted
with `RepaintBoundary.toImage(pixelRatio: 2)` and wrapped **zero-copy**
into a `gpu.Texture` via `Texture.fromImage`, then drawn as quads on a
cover-flow carousel: depth-tested, 4x MSAA, premultiplied-alpha blending,
floor reflections, backside dimming. Poke a switch in the panel and the
3D copy updates.

The 3D copies are also **clickable**: a tap on the stage is unprojected
(inverse view-projection ray vs. each front-facing card quad) into
card-local UV, mapped to the real widget's on-screen rect, and dispatched
as a synthetic pointer down/up through `GestureBinding` — so pressing the
Follow button on the rotating 3D card presses the real button, and the
new state flows back into the scene on the next capture.

Gotcha this uncovered: after the first `toImage`, the context's
`defaultColorFormat` can start returning `PixelFormat.unknown` (a
wide-gamut snapshot format flutter_gpu can't map), which broke surfaces
and MSAA attachments mid-session. Mitigations: formats are queried once
and cached with fallbacks (`stableColorFormat`), the app opts out of wide
gamut (`FLTEnableWideGamut=false`), and the capture path falls back to a
CPU pixel copy when `fromImage` cannot wrap the snapshot.

## Widget FX: GpuShaderBox and GpuShaderSampler

`lib/src/gpu_widgets.dart` is the Flutter GPU equivalent of
flutter_shaders' `ShaderBuilder`/`AnimatedSampler`, built by combining
this app's runtime shader compiler with flutter_scene's exported
`WidgetTexture` capture pipeline:

- `GpuShaderBox` renders a runtime-compiled fragment shader in an
  ordinary widget box (inline GLSL string or asset, `FragInfo` contract).
- `GpuShaderSampler` applies a fragment shader **over a live child
  widget**: the child is hosted invisibly and captured zero-copy into a
  `gpu.Texture` (bound as `uniform sampler2D u_child`), and pointer input
  is forwarded through `WidgetTextureController` in UV space, so buttons,
  switches, and sliders keep working under the effect. Child state
  survives switching effects.

The Widget FX tile demonstrates it: a real card behind selectable
ripple / halftone / frost effects, all compiled at runtime from inline
GLSL, interactive throughout.

## Visual language

The shared deck theme uses warm paper (`#EFECE6`), ink (`#2C2E31`), spruce
(`#4F6F6A`), and stoneware tones. Individual demos may replace that chrome when
the subject requires a different visual reference, such as the Windows XP
windowing slide.

## flutter_scene demos

The two "Scene:" tiles use [flutter_scene](https://pub.dev/packages/flutter_scene),
the 3D engine built on the same Flutter GPU API the rest of the gallery
drives by hand. They render through its `SceneView` widget (which owns its
frame loop), with `OrbitCameraController` + `CameraControls` for input and
`EnvironmentSettings` presets from the package's own agent skills (installed
under `.claude/skills/` by `dart run flutter_scene:init`). The Fox model is
converted from `assets/Fox.glb` to the engine's `.fsceneb` format at build
time by the `hook/build.dart` the init command wrote. Fox model: Khronos
glTF sample, model by PixelMannen (CC0), rig/animation by @tomkranis
(CC-BY 4.0).

The Still Life also demonstrates `WidgetComponent`: a real, interactive
Flutter widget (the floating "Scene Controls" card) lives on a billboard
quad inside the 3D scene — `SceneView` hosts the subtree invisibly,
re-captures it every frame, and raycasts pointer input onto the surface,
so clicking the in-scene switch toggles the pillars and the slider drives
the orbit speed.

Launch placement helper: `GPU_PLAYGROUND_SCREEN=fast` opens 1280×800 on the
highest-refresh display (ProMotion), `=main` on the main display.

## Platform and distribution constraints

- There is no GLSL compiler inside the engine (Impeller precompiles by
  design), which is why the app shells out to `impellerc`. Compiles take
  ~150–600 ms.
- macOS App Sandbox is disabled in the Runner entitlements so the app may
  spawn `impellerc` — fine for a local dev playground, do not ship a
  distributable build this way without revisiting.
- `dart run tool/live_compiler_smoke.dart` smoke-tests the compiler
  outside the app.
