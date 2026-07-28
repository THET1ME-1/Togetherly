allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // androidx.datastore держим на 1.1.7, пока не выйдет версия, собранная
    // свежим NDK.
    //
    // Play Console на выпуске 1.18.1 (126): «в приложении могут возникать сбои
    // на устройствах со страницами памяти размером 16 КБ» —
    // `libdatastore_shared_counter.so` из datastore 1.2.0 помечена NDK r20
    // (у 1.1.7 — r25c). Сегменты у обеих выровнены по 0x4000, но r22 и ниже
    // требуют ещё и `-Wl,-z,common-page-size=16384`, поэтому Play помечает
    // такие библиотеки как опасные на 16 КБ. Сами мы их не собираем: они
    // приезжают готовыми из AndroidX через `shared_preferences_android`
    // (flutter#182898).
    //
    // Снимать, когда `shared_preferences_android` перейдёт на datastore,
    // собранный NDK r28+. Проверять так:
    //   unzip -p <aar> jni/arm64-v8a/libdatastore_shared_counter.so > /tmp/x.so
    //   readelf -n /tmp/x.so   # в .note.android.ident должен быть r28 и выше
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.datastore") {
                useVersion("1.1.7")
                because("datastore 1.2.0 собран NDK r20 — Play ругается на 16 КБ")
            }
        }
    }
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.addAll(listOf("-Xlint:-options"))
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
