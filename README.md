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
| Live Editor | ShaderToy-style: type GLSL, ⌘⏎ compiles it at runtime and hot-swaps the pipeline |

Toolbar: play/pause, time scale, and render-scale (50/75/100 % of native
resolution). The stats readout shows live fps and the surface size in
physical pixels.

## Requirements

- Flutter **master** channel (Flutter GPU is not available on stable).
  The repo is pinned via `.fvmrc` for [fvm](https://fvm.app) users.
- Native assets enabled: `flutter config --enable-native-assets`
  (needed for the shader build hook).
- macOS with Impeller (default on master; also forced via
  `FLTEnableImpeller` in `macos/Runner/Info.plist`).

## Run

```sh
fvm use master          # or make sure `flutter` is the master channel
flutter config --enable-native-assets
flutter run -d macos
```

## How it works

- `shaders/*.vert|frag` — Impeller-dialect GLSL, compiled by `impellerc`
  into a single shader bundle.
- `playground.shaderbundle.json` — the bundle manifest (shader name → file).
- `hook/build.dart` — a Dart build hook (`package:hooks` +
  `package:flutter_gpu_shaders`) that compiles the bundle on every build
  into `build/shaderbundles/playground.shaderbundle`, which is listed as a
  regular Flutter asset.
- `lib/src/gpu_kit.dart` — shader-bundle loading and a reflection-based
  `UniformWriter` (uniform member offsets come from shader reflection, so
  no hardcoded std140 layout math).
- `lib/src/surface_view.dart` — hosts a `GpuImageSurface`: each Ticker
  tick acquires a frame texture, lets the active demo encode its render
  pass(es), presents, and paints `surface.currentImage`.
- `lib/src/demos/` — one class per demo. 3D demos build their own
  pipelines, vertex/index buffers, and depth/MSAA attachments; the
  fullscreen shader-art demos share a 3-vertex fullscreen-triangle
  pipeline and a common `FragInfo` uniform contract (resolution, pointer,
  time, 4 generic params).

## Live Editor

The last tile is a runtime shader editor. There is no GLSL compiler in the
engine (Impeller precompiles by design), so the app shells out to the
SDK's own `impellerc` (`lib/src/live_compiler.dart` finds it via
`$IMPELLERC`, the `flutter` on PATH, or FVM installs), compiles the typed
source plus a fixed fullscreen vertex shader into a temp shader bundle
(~100-500 ms), loads it with `gpu.ShaderLibrary.fromBytes`, and swaps the
render pipeline on the next frame. Compile errors from `impellerc` show
in a console under the editor with `LiveFragment:<line>` positions.
Uniforms bind leniently by reflection, so trimming members from the
`FragInfo` block is fine.

Notes:
- macOS App Sandbox is disabled in the Runner entitlements so the app may
  spawn `impellerc` — fine for a local dev playground, do not ship a
  distributable build this way without revisiting.
- `dart run tool/live_compiler_smoke.dart` smoke-tests the compiler
  outside the app.
