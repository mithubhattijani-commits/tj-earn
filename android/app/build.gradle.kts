plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tjearn.tj_earn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Stable day-1 signing key for TJ Earn. The CI workflow decodes the
    // KEYSTORE_BASE64 secret into android/app/tjearn.keystore and passes
    // the passwords via environment variables. The keystore file itself is
    // never committed to the repo (see .gitignore). Without it, builds fall
    // back to the standard debug key (local development only) — never ship
    // a build signed with a different key, or installed users would need
    // to uninstall before updating.
    val tjearnKeystoreFile = file("tjearn.keystore")
    if (tjearnKeystoreFile.exists()) {
        signingConfigs.create("tjearn") {
            storeFile = tjearnKeystoreFile
            storePassword = System.getenv("KEYSTORE_STORE_PASSWORD")
            keyAlias = "tjearn"
            keyPassword = System.getenv("KEYSTORE_KEY_PASSWORD")
        }
    }

    defaultConfig {
        // FIXED FOREVER: com.tjearn.app. Never change this — changing the
        // package name breaks the in-app update chain for installed users.
        applicationId = "com.tjearn.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            if (tjearnKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("tjearn")
            }
        }
        release {
            if (tjearnKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("tjearn")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
