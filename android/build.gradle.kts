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

// isar_flutter_libs 3.1.0+1 predates AGP 8 and is unmaintained upstream:
// it declares no `namespace` (mandatory since AGP 8) and pins
// compileSdkVersion 30, below the API 34+ floor its androidx transitives
// demand. Patch both after the module evaluates so its own build.gradle
// cannot override the values back.
subprojects {
    if (name == "isar_flutter_libs") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                if (namespace == null) {
                    namespace = "dev.isar.isar_flutter_libs"
                }
                compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
