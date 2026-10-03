plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = providers.environmentVariable("POLEVAYA_KEYSTORE_PATH").orNull
val releaseKeystorePassword = providers.environmentVariable("POLEVAYA_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("POLEVAYA_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("POLEVAYA_KEY_PASSWORD").orNull
val releaseSigningReady = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

gradle.taskGraph.whenReady {
    if (!releaseSigningReady && allTasks.any { it.path.startsWith(":app:") && it.name.contains("Release") }) {
        throw GradleException("Android release signing variables are required. Use tools/build_android_release.ps1.")
    }
}

android {
    namespace = "ru.obedmoscow.polevayakuhnya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.obedmoscow.polevayakuhnya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("ownerRelease") {
                storeFile = file(requireNotNull(releaseKeystorePath))
                storePassword = requireNotNull(releaseKeystorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("ownerRelease")
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
