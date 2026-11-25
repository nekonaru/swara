plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A stable release key is supplied by CI through GitHub Secrets. The file is
// decoded into the runner temp directory and never lives in this repository.
// Local builds without the env vars keep using the default debug key.
val releaseKeystorePath = System.getenv("SWARA_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("SWARA_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("SWARA_KEY_ALIAS")
val releaseKeyPassword = System.getenv("SWARA_KEY_PASSWORD")

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
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-apk-splits)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystorePath != null &&
            releaseStorePassword != null &&
            releaseKeyAlias != null &&
            releaseKeyPassword != null
        ) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystorePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 + resource shrinking: strips unused Java/Kotlin code and
            // resources from the release APK. Conservative keeps for the
            // plugins that touch the framework through reflection/JNI are in
            // proguard-rules.pro. Verify playback, scanning and the home
            // widget after installing an update built with this config.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // MediaBrowserCompat/MediaControllerCompat for the Quick Settings tile.
    implementation("androidx.media:media:1.7.0")
    // Required for the Theme.AppCompat.* themes in styles.xml (AudioServiceFragmentActivity).
    implementation("androidx.appcompat:appcompat:1.7.0")
    // Android 12+ splash screen API (navy tile + brand glyph at cold start).
    implementation("androidx.core:core-splashscreen:1.0.1")
}
