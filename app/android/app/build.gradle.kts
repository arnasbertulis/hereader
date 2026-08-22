plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from the environment, never checked in. All four
// must be set or the release build falls back to the debug keys.
val releaseKeystorePath: String? = System.getenv("HEREADER_KEYSTORE_PATH")
val releaseKeystorePassword: String? = System.getenv("HEREADER_KEYSTORE_PASSWORD")
val releaseKeyAlias: String? = System.getenv("HEREADER_KEY_ALIAS")
val releaseKeyPassword: String? = System.getenv("HEREADER_KEY_PASSWORD")
val hasReleaseSigning =
    releaseKeystorePath != null &&
        releaseKeystorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

android {
    namespace = "com.arnasbertulis.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.arnasbertulis.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "HEREADER_KEYSTORE_PATH/HEREADER_KEYSTORE_PASSWORD/HEREADER_KEY_ALIAS/" +
                        "HEREADER_KEY_PASSWORD not all set; release build signed with debug keys."
                )
                signingConfigs.getByName("debug")
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
