import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging — processes android/app/google-services.json
    id("com.google.gms.google-services")
}

// Release signing config, loaded from android/key.properties (gitignored). When
// the file is absent (e.g. CI without the keystore) we fall back to debug signing
// so debug builds still work; a release build then simply won't be Play-signable.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.orb.guard"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.orb.guard"
        minSdk = flutter.minSdkVersion
        // Google Play requires a recent target API to release; match compileSdk.
        targetSdk = 36
        // Bump on every Play upload (1 = draft, 2 = targetSdk36, 3 = dropped the
        // unused READ_CALL_LOG permission).
        versionCode = 5
        versionName = "1.0"
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real upload keystore when present (Play release); otherwise
            // fall back to debug so local/CI debug builds still work.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        getByName("debug") {
            // Debug build configuration
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.20")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
