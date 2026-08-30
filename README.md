# GPU Playground

A macOS desktop **presentation** built with
[flutter_deck](https://pub.dev/packages/flutter_deck), combining native
multi-window demos, a live 3D landscape, an interactive design editor, and a
gallery of GPU rendering demos built directly on
[Flutter GPU](https://github.com/flutter/flutter/blob/master/engine/src/flutter/docs/impeller/Flutter-GPU.md)
(`package:flutter_gpu`), Flutter's low-level Impeller graphics API.
Every pixel in the gallery's viewport comes from hand-written render
passes and impellerc-compiled GLSL — no Canvas, no CustomPaint drawing,
no `FragmentProgram`.

## The deck

`lib/src/deck/` is a 31-slide flutter_deck presentation in one quiet
Scandinavian visual system. Arrow keys drive it,
`⌘.` opens the slide drawer.

Presentation metadata is configured once in `lib/src/deck/config.dart`.
Its title, author, date, and place are combined into the footer shared by
all numbered slides.

| # | Slide |
| --- | --- |
| 1–4 | Opening question, live poll, desktop screenshot, and the 2020 talk |
| **5** | **Flutter desktop timeline** — six stepped milestones from early access to multi-window |
| 6–11 | Windowing story, detachable browser tabs, panels, and a floating edge window |
| 12–18 | Flutter GPU, flutter_scene, and the live design editor |
| 19–25 | Desktop apps, Flutter Zero, Flocker, and engine experimentation |
| 26–29 | Visible's desktop development and agent workflows |
| **30** | **Sources** — a photograph-friendly reference list |
| **31** | **Q&A close** — the callback to the opening desktop screenshot |

### Slide 2: live poll results

The poll slide fetches results as soon as it opens and refreshes them every
two seconds while it remains visible. Bars and vote totals animate between
responses. Pass the endpoint at build or run time:

```sh
flutter run -d macos \
  --dart-define=POLL_RESULTS_URL=https://example.com/poll-results.json \
  --dart-define=POLL_VOTE_URL=https://forms.gle/example \
  --dart-define=POLL_VOTE_LABEL=vote.example.com
```

When `POLL_VOTE_URL` is set, the slide shows a continuously moving “VOTE NOW”
strip along its lower edge. `POLL_VOTE_LABEL` is the short, audience-readable
text shown in that strip; without it, the URL is shortened to its host and
path. Omit `POLL_VOTE_URL` to hide the strip.

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

### Slide 15: the flyover

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
- `SceneView(warmUp: true)` gates the view behind a reveal that never
  fires in this setup, leaving the slide blank.

`GPU_FLYOVER_CAPTURE=1` drops the dithered screen-space effects, whose
noise inflates a captured frame past what screenshot tooling carries.

## Demos

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
| Design Canvas | Serializable graphics editor with components, frame shaders, snapping, history, and layer hierarchy |

Toolbar: play/pause, time scale, and render-scale (50/75/100 % of native
resolution). The stats readout shows live fps and the surface size in
physical pixels.

The frame loop is vsync-driven (a `Ticker` per frame), so the app runs at
whatever the display delivers — verified at **120 fps** on a MacBook Pro
ProMotion panel (all demos, including the raymarchers at full 2x retina)
and 60 fps on a 60 Hz external display. Launch with
`GPU_PLAYGROUND_PROMOTION=1` to open the window on the highest-refresh
screen automatically, or just drag it there.

## Every demo is editable

There is no precompiled shader bundle: **all GLSL is compiled at
runtime**. Each demo declares its sources (`shaders/*.vert|frag`, shipped
as plain text assets); on first open they are compiled by the SDK's
`impellerc` and loaded with `gpu.ShaderLibrary.fromBytes`. The `{ }`
toolbar button opens a shader editor for the current demo — one tab per
stage — and ⌘⏎ recompiles and hot-swaps its pipelines while it runs.
Compile errors show inline with `name:line` positions and the previous
pipeline keeps rendering. On Widget Stage the side panel has
Widgets / GLSL tabs.

## Requirements

- Flutter **master** channel (Flutter GPU is not available on stable).
  The repo is pinned via `.fvmrc` for [fvm](https://fvm.app) users.
- Flutter's experimental desktop windowing feature enabled once for the SDK:
  `fvm flutter config --enable-windowing`. The windowed browser on slide 9 uses the
  first-party `WindowController` / `Window` API, so detached tabs share the
  same widget tree and application state as the deck.
- The `impellerc` binary from a Flutter SDK. It is auto-discovered from
  the `flutter` on PATH or FVM installs; set `$IMPELLERC` to override.
- macOS with Impeller (default on master; also forced via
  `FLTEnableImpeller` in `macos/Runner/Info.plist`).

## Run

```sh
fvm use master          # or make sure `flutter` is the master channel
flutter run -d macos
```

The app opens on slide 1 of the deck. The gallery described below is slide 14;
everything in it works exactly as it did standalone.

## How it works

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
  `slides.dart` (the ordered slide list), `slides/1.dart` through
  `slides/31.dart` (one numbered file per slide), and `page.dart` (the
  shared slide layout and type ramp).
- `lib/src/flyover/` — `world.dart` (the procedural landscape, built once
  at launch so slide 15 has nothing left to do), `camera_path.dart` (the
  flight), `flyover_view.dart` (the widget, the wash, and the step wiring).
- `lib/src/gallery.dart` — the demo gallery shell, hosted by slide 14.
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

## Widget FX — GpuShaderBox / GpuShaderSampler

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

## Design language

The gallery uses a quiet Scandinavian palette throughout — warm paper
(#EFECE6), ink (#2C2E31), spruce (#4F6F6A), and stoneware tones (clay,
sage, dusty blue, sand) — in both the app chrome and the demo content.

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

## Notes

- There is no GLSL compiler inside the engine (Impeller precompiles by
  design), which is why the app shells out to `impellerc`. Compiles take
  ~150–600 ms.
- macOS App Sandbox is disabled in the Runner entitlements so the app may
  spawn `impellerc` — fine for a local dev playground, do not ship a
  distributable build this way without revisiting.
- `dart run tool/live_compiler_smoke.dart` smoke-tests the compiler
  outside the app.
