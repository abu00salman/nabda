import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

// Release signing: reads android-app/keystore.properties (gitignored, never commit it).
// Until that file exists, release builds fall back to the debug keystore so the
// project still builds end to end — see android-app/README.md for how to generate
// a real signing key before shipping anywhere.
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}

android {
    namespace = "com.playnabda.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.playnabda.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        // The real, deployed site. Nabda's own service worker (sw.js) already caches
        // the app shell for offline play, and the leaderboard lives server-side on
        // Cloudflare — bundling a second copy of index.html into the APK would just
        // drift out of sync with every web deploy. See README.md "Architecture".
        buildConfigField("String", "BASE_URL", "\"https://playnabda.com/\"")
    }

    signingConfigs {
        if (keystorePropsFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
            // Points at the same production site by default (there's no staging
            // server) but as its own BuildConfig constant, so you can flip this to
            // e.g. "http://10.0.2.2:8080/" for an emulator talking to a local static
            // server, or your LAN IP for a physical device, without touching release.
            buildConfigField("String", "BASE_URL", "\"https://playnabda.com/\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystorePropsFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes.add("META-INF/*.version")
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.ktx)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.material)
}
