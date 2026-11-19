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

// TJ Racing 3D (Unity-as-a-Library, v1.0.31) — PLACEHOLDER, NOT
// WIRED YET. The sibling Unity agent is building the export; it
// lands in android/unityLibrary/ (exported via
// `Flutter Embed -> Export project to Flutter app`). The include
// below activates automatically once unityLibrary/build.gradle
// exists — until then the app builds exactly as before (no Unity).
// When the export lands, also wire (see
// lib/games/tj_racing/UNITY_CONTRACT.md):
//   - android/app/build.gradle.kts:
//     implementation(project(":unityLibrary"))
//   - flatDir repo for unityLibrary/libs
//   - android/gradle.properties:
//     unityStreamingAssets=<value from the Unity console log>
// Pinned Unity version: 2022.3.62f2 or newer (flutter_embed_unity
// 2.0.0 requirement). Do NOT invent a fake unityLibrary.
if (file("unityLibrary/build.gradle").exists()) {
    include(":unityLibrary")
}
