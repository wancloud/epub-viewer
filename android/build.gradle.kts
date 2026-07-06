allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Android plugin subproject (file_picker, window_manager, shared_preferences,
// flutter_plugin_android_lifecycle, ...) to compile against SDK 36. Setting compileSdk only
// on :app isn't enough — plugin modules keep their own (older, e.g. 34) compileSdk, and
// flutter_plugin_android_lifecycle's AAR metadata requires consumers to compile against 36,
// so the build fails without this uniform override.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
