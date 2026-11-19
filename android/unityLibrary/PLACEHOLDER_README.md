# TJ Racing 3D Unity export goes HERE (v1.0.31) — WIRED, delivered by CI

This directory holds ONLY this file in git. The real `unityLibrary`
(Unity 2022.3.62f2 export, IL2CPP, arm64-v8a + armeabi-v7a) is NEVER
committed — it is 314 MB and exceeds GitHub's 100 MB/file limit.

Delivery: `unityLibrary.zip` is a release asset on the tj-racing repo.
The tj-earn CI workflow downloads it and unzips it into THIS directory
(`android/unityLibrary/`) BEFORE the Flutter build, then deletes this
placeholder file. Local builds without the export work exactly as
before (no Unity) — `android/settings.gradle.kts` includes
`:unityLibrary` only when `unityLibrary/build.gradle` exists, and
`android/app/build.gradle.kts` adds the `implementation(project(...))`
dependency + flatDir repo only under the same guard.

Wiring (done on branch `remove-arrow-puzzle`, v1.0.31):

1. `android/app/build.gradle.kts`:
   `implementation(project(":unityLibrary"))` + flatDir repo for
   `unityLibrary/libs` (both guarded on the export existing).
2. `android/gradle.properties`:
   `unityStreamingAssets=` (empty — the Unity exporter console log
   printed no streaming-asset extensions).
3. The export's own `build.gradle` was patched for AGP 9.1.0 INSIDE
   the zip only (lintOptions→lint, aaptOptions→androidResources,
   packagingOptions→packaging, compileSdk/minSdk/targetSdk property
   form). The on-disk export stays pristine; the zip is the delivery
   artifact. The local Gradle build is blocked by the sandbox, so the
   v1.0.31 CI build is the first real Gradle test of this wiring.

Pinned Unity version: 2022.3.62f2 or newer (flutter_embed_unity
2.0.0 requirement). Do NOT invent a fake unityLibrary.
