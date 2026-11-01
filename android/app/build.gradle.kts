import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = System.getenv("UHC_SIGNING_PROPERTIES_FILE")
    ?.takeIf { it.isNotBlank() }
    ?.let { location ->
        Properties().apply { file(location).inputStream().use { load(it) } }
    }

android {
    namespace = "com.example.uhc"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.uhc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // Required for Firebase
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        releaseSigningProperties?.let { signing ->
            create("privateRelease") {
                storeFile = file(requireNotNull(signing.getProperty("storeFile")))
                storePassword = requireNotNull(signing.getProperty("storePassword"))
                keyAlias = requireNotNull(signing.getProperty("keyAlias"))
                keyPassword = requireNotNull(signing.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("privateRelease")
                ?: if (System.getenv("UHC_ALLOW_DEBUG_SIGNED_LOCAL_RELEASE") == "true") {
                    signingConfigs.getByName("debug")
                } else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Also apply proguard rules in debug to prevent TypeToken crash
            // from flutter_local_notifications with R8
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
