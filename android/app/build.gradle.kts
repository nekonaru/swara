plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nikodwidharma.offline_music_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by audio_service and the AppCompat theme resources.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.nikodwidharma.offline_music_player"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-apk-splits)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            // NOTE: enabling isMinifyEnabled or isShrinkResources lets R8 strip
            // native classes used through JNI and reflection by plugins such as
            // on_audio_query. That fails only on a real device and nowhere else,
            // so minification stays off on purpose.
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Required for the Theme.AppCompat.* themes in styles.xml (AudioServiceFragmentActivity).
    implementation("androidx.appcompat:appcompat:1.7.0")
}
