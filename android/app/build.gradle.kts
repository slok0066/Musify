plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.musify.musify"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.musify.musify"
        // Musify targets Android 8.0 (API 26) through Android 16 (API 36).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // NOTE: ABI restriction is deliberately NOT expressed as
        // `ndk.abiFilters` here. Flutter's Gradle plugin rewrites those filters
        // during apply(), and AGP flatly rejects `ndk.abiFilters` existing at
        // the same time as `splits.abi`:
        //   "Conflicting configuration : 'armeabi-v7a,arm64-v8a' in ndk
        //    abiFilters cannot be present when splits abi filters are set"
        // which breaks `--split-per-abi`. The ARM-only rule is enforced one
        // step later instead — see the `packaging` block below.
    }

    // PRD §1: ARM64-v8a + ARMv7 only, no x86/x86_64 emulation payload.
    //
    // Packaging filters run *after* variant configuration, so unlike
    // `ndk.abiFilters` they cannot be reset by the Flutter plugin and cannot
    // conflict with `splits.abi`. Anything x86 that a third-party plugin
    // ships (SoLoud ships x86_64 emulator libraries) is stripped here.
    packaging {
        jniLibs {
            excludes += listOf("lib/x86/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
