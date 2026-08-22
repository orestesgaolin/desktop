# GPU Playground

A macOS desktop gallery of GPU rendering demos built directly on
[Flutter GPU](https://github.com/flutter/flutter/blob/master/engine/src/flutter/docs/impeller/Flutter-GPU.md)
(`package:flutter_gpu`), Flutter's low-level Impeller graphics API.
Every pixel in the viewport comes from hand-written render passes and
impellerc-compiled GLSL — no Canvas, no CustomPaint drawing, no
`FragmentProgram`.

## Demos

| Demo | What it shows |
| --- | --- |
| Hello Triangle | Minimal pipeline: one vertex buffer, two shaders, animated on the GPU |
| Neon Cube | Indexed draw, depth buffer, back-face culling, 4x MSAA resolve |
| Galaxy Particles | 40k instanced billboards (`VertexStepMode.instance`), additive blending |
| SDF Raymarch | Fullscreen raymarcher: smooth-min morphs, soft shadows, AO, fog |
| Golden Hour Ocean | Raymarched wave heightfield with fresnel, sun glitter, foam |
| Metaballs | Analytic 2D iso-surface with gradient shading (one ball follows the pointer) |
| Plasma | Domain-warped oldschool plasma with cosine palettes |
| Mandelbrot | Smooth escape-time fractal; drag to pan, scroll for anchored zoom |
| Widget Stage | Real, live Flutter widgets captured as GPU textures and spun on a 3D carousel |
| Scene: PBR Studio | [flutter_scene](https://pub.dev/packages/flutter_scene): scene graph, PBR + IBL, shadow-casting sun, SSR, bloom, orbit camera |
| Scene: Animated Fox | flutter_scene glTF asset pipeline + blended skeletal animation (Khronos sample Fox) |
| Live Editor | ShaderToy-style: type GLSL, ⌘⏎ compiles it at runtime and hot-swaps the pipeline |

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
- The `impellerc` binary from a Flutter SDK. It is auto-discovered from
  the `flutter` on PATH or FVM installs; set `$IMPELLERC` to override.
- macOS with Impeller (default on master; also forced via
  `FLTEnableImpeller` in `macos/Runner/Info.plist`).

## Run

```sh
fvm use master          # or make sure `flutter` is the master channel
flutter run -d macos
```

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
