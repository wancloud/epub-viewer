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

// Force every Android plugin subproject (file_picker, window_manager, shared_preferences,
// flutter_plugin_android_lifecycle, ...) to compile against SDK 36. Setting compileSdk only
// on :app isn't enough — plugin modules keep their own (older, e.g. 34) compileSdk, and
// flutter_plugin_android_lifecycle's AAR metadata requires consumers to compile against 36.
//
// This must run in `afterEvaluate` (not `pluginManager.withPlugin`): a plugin like
// file_picker sets its own `compileSdk 34` *inside* its `android {}` block during
// evaluation, which happens AFTER the withPlugin callback fires — so a withPlugin override
// gets clobbered back to 34. afterEvaluate runs after the plugin has fully configured
// itself, so our 36 wins.
//
// Ordering matters: we register the afterEvaluate override on ALL subprojects in this pass
// FIRST, while none has been evaluated yet. Only afterwards do we call
// evaluationDependsOn(":app") — that call eagerly evaluates :app, and if it ran before we
// registered :app's afterEvaluate we'd hit "project already evaluated".
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            androidExtension.compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
