pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// TJ Racing 3D (Unity-as-a-Library, v1.0.31) — WIRED. The Unity export
// (Unity 2022.3.62f2, IL2CPP, arm64-v8a + armeabi-v7a) lands in
// android/unityLibrary/ via the CI release-asset download
// (unityLibrary.zip from the tj-racing release) before the Flutter
// build; the include below activates as soon as
// unityLibrary/build.gradle exists. Wiring done on this branch:
//   - android/app/build.gradle.kts:
//     implementation(project(":unityLibrary")) + flatDir for
//     unityLibrary/libs (both guarded on unityLibrary/build.gradle
//     existing, so local builds without the export still work)
//   - android/gradle.properties: unityStreamingAssets= (empty per the
//     Unity exporter console log — no streaming-asset extensions)
//   - the export's own build.gradle was patched for AGP 9.1.0 inside
//     the zip only (lintOptions→lint, aaptOptions→androidResources,
//     packagingOptions→packaging, compileSdk/minSdk/targetSdk property
//     form); the on-disk export stays pristine — the zip is the
//     delivery artifact. See the v1.0.31 wiring report.
// Pinned Unity version: 2022.3.62f2 or newer (flutter_embed_unity
// 2.0.0 requirement). Do NOT invent a fake unityLibrary.
if (file("unityLibrary/build.gradle").exists()) {
    include(":unityLibrary")
}
