# PLACEHOLDER — TJ Racing 3D Unity export goes HERE (v1.0.31)

This directory is intentionally EMPTY (no `unityLibrary` yet).

The sibling Unity agent is building the TJ Racing 3D Unity project
(pinned Unity **2022.3.62f2 or newer**, 2022.3 LTS). When it is ready
it is exported from Unity via
`Flutter Embed -> Export project to Flutter app` (android) into
THIS directory, which then contains the real `unityLibrary`
(`build.gradle`, `src/`, `libs/`, ...).

What happens automatically once the export lands:

- `android/settings.gradle.kts` already contains a conditional
  `include(":unityLibrary")` — it activates as soon as
  `unityLibrary/build.gradle` exists. Nothing else to change there.

What STILL needs wiring at that point (coordinator follow-up —
do NOT guess these values, take them from the real export):

1. `android/app/build.gradle.kts`:
   `implementation(project(":unityLibrary"))` in `dependencies`.
2. A `flatDir` repository pointing at `unityLibrary/libs`
   (settings/root build file).
3. `android/gradle.properties`:
   `unityStreamingAssets=<value printed by the Unity console log
   after export>` (often blank).
4. Verify the export's own `build.gradle` (Unity 2022.3 pins Gradle
   7.5.1 / AGP 7.4.2 / NDK r23b / JDK 11) builds inside this app
   (AGP 9.1.0 / JDK 17) before the v1.0.31 CI run.

Until then: a release build CANNOT link Unity (expected — the
Flutter analyzer + tests still run clean), the racing tile stays
hidden (`games.tj_racing.enabled` is false in the live config),
and no fake library is invented here.
