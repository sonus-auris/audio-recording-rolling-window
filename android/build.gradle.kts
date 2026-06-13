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

// Some Flutter plugins (e.g. geocoding_android) pin an older compileSdk (33) and
// do not inherit the app's, which newer AndroidX deps reject (they require >=34).
// Force every Android subproject up to a modern compileSdk. Reflection keeps this
// independent of AGP types that aren't on the root build script's classpath.
fun Project.forceCompileSdk() {
    val androidExt = extensions.findByName("android") ?: return
    runCatching {
        androidExt.javaClass
            .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
            .invoke(androidExt, 36)
    }
}
subprojects {
    // evaluationDependsOn(":app") above can leave some subprojects already
    // evaluated by the time this runs; afterEvaluate throws on those, so apply
    // directly when evaluated and hook afterEvaluate otherwise.
    if (state.executed) {
        forceCompileSdk()
    } else {
        afterEvaluate { forceCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
