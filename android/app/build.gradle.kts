import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val requiredReleaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val hasReleaseSigningProperties = keystorePropertiesFile.exists() &&
    requiredReleaseSigningKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.zarathu.seil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.zarathu.seil"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigningProperties) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Play uploads must fail before a debug-signed artifact is produced.
            if (hasReleaseSigningProperties) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

tasks.matching {
    it.name == "assembleRelease" || it.name == "bundleRelease" || it.name == "packageReleaseBundle"
}.configureEach {
    doFirst {
        if (!hasReleaseSigningProperties) {
            throw GradleException(
                "Release signing is not configured. Copy android/key.properties.example to " +
                    "android/key.properties and point it at a local upload keystore.",
            )
        }

        val storeFilePath = keystoreProperties.getProperty("storeFile")
        val releaseKeystore = rootProject.file(storeFilePath)
        if (!releaseKeystore.exists()) {
            throw GradleException(
                "Release signing keystore does not exist: ${releaseKeystore.path}",
            )
        }
    }
}
