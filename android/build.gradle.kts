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
// flutter_plugin_android_lifecycle's AAR metadata requires consumers to compile against 36.
// Configure via pluginManager.withPlugin (fires as the Android plugin is applied) rather
// than afterEvaluate, which throws "project already evaluated" because of the
// evaluationDependsOn(":app") above.
subprojects {
    listOf("com.android.library", "com.android.application").forEach { pluginId ->
        pluginManager.withPlugin(pluginId) {
            (extensions.getByName("android") as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
