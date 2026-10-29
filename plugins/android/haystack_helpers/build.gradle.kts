// Godot Android plugin (v2): system accessibility settings for Haystack Co. (design D14).
// G2 adds the Test Lab Game Loop helper to this same plugin.
plugins {
    id("com.android.library")
}

val godotVersion = "4.7.2.stable" // keep in sync with the README version pin

android {
    namespace = "com.brewingbytes.haystack.helpers"
    compileSdk = 36
    defaultConfig {
        minSdk = 24
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

base {
    archivesName.set("haystack-helpers")
}

dependencies {
    compileOnly("org.godotengine:godot:$godotVersion")
}

// Copy the built AARs into the Godot addon so the export plugin can find them.
val copyAars by tasks.registering(Copy::class) {
    from(layout.buildDirectory.dir("outputs/aar"))
    include("haystack-helpers-debug.aar", "haystack-helpers-release.aar")
    into(rootDir.resolve("../../addons/haystack_android/bin"))
}
tasks.named("assemble") { finalizedBy(copyAars) }
