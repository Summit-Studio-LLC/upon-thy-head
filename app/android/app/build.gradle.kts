import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The phone check's prepared recordings, copied in only for --dart-define=PHONE_CHECK=true.
// A normal build leaves the folder empty, so the apk does not grow (PhoneCheck.kt).
// A File, not a Provider: AGP 9 refuses a Provider in sourceSets.
val phoneCheckRoot = File(layout.buildDirectory.get().asFile, "generated/phoneCheckAssets")
val phoneCheck = (findProperty("dart-defines") as? String).orEmpty()
    .split(',')
    .filter { it.isNotEmpty() }
    .mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
    .any { it == "PHONE_CHECK=true" }

val audioDir = file("../../integration_test/audio")
val bundlePhoneCheckAudio = tasks.register("bundlePhoneCheckAudio") {
    val enabled = phoneCheck
    val src = audioDir
    val dst = phoneCheckRoot
    inputs.property("phoneCheck", enabled)
    if (enabled) inputs.dir(src)
    outputs.dir(dst)
    doLast {
        dst.deleteRecursively()
        dst.mkdirs()
        if (enabled) {
            val out = File(dst, "phone_check").apply { mkdirs() }
            for (name in listOf("en.m4a", "es.m4a")) {
                File(src, name).copyTo(File(out, name), overwrite = true)
            }
        }
    }
}

android {
    namespace = "dev.summitstudio.uponthyhead"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    sourceSets.getByName("main").assets.srcDir(phoneCheckRoot)

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

tasks.named("preBuild").configure { dependsOn(bundlePhoneCheckAudio) }
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("Assets")) dependsOn(bundlePhoneCheckAudio)
}
