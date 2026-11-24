import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Play upload key (android/key.properties, never committed; the key itself is in important/).
// Without it a release build is signed with the debug key, which runs on an emulator and which
// Google Play refuses.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }

android {
    namespace = "dev.summitstudio.uponthyhead"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The iPhone app's bundle id (dev.summitstudio.uponThyHead), in Android's lower case.
        // Fixed for ever once the app is on Google Play.
        applicationId = "dev.summitstudio.uponthyhead"
        // Android 13 (the owner's ruling, 2026-11-16; docs/android-plan.md 11.1).
        minSdk = 33
        // Google Play's requirement from 31 August 2026 (android-plan.md 8.4).
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Our upload key; Google Play signs again with its own key before a phone gets the app.
            signingConfig = signingConfigs.getByName(if (keystorePropertiesFile.exists()) "upload" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Play Integrity, standard request: proof that a link request comes from this app (ProofChannel.kt)
    implementation("com.google.android.play:integrity:1.4.0")
}

flutter {
    source = "../.."
}
