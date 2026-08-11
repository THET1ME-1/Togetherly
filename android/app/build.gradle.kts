import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.togetherly.love"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    // Нативные библиотеки в APK по умолчанию лежат НЕСЖАТЫМИ: 47,8 МБ у arm64,
    // из них libapp 18,3, WebRTC 11,5 и движок Flutter 10,8. Deflate ужимает их
    // до 21,1 МБ (проверено на живых файлах сборки 1.24.0), то есть загрузка
    // падает вдвое — а APK у нас скачивают целиком и по мобильному интернету:
    // самообновление тянет его с релизов GitHub, RuStore тоже отдаёт файл.
    //
    // Расплата — распаковка на устройстве: система кладёт библиотеки ещё и в
    // /data, места занимает больше, установка чуть дольше. Для AAB это чистый
    // вред: Play жмёт при доставке сам, а несжатые .so на устройстве не дублирует
    // — поэтому у сборки бандла флаг снимается. Задачу отличаем по её имени,
    // другого способа увидеть тип выхода в AGP нет.
    val buildingBundle = gradle.startParameter.taskNames.any {
        it.contains("bundle", ignoreCase = true)
    }
    packaging {
        jniLibs {
            useLegacyPackaging = !buildingBundle
        }
    }

    defaultConfig {
        applicationId = "com.togetherly.love"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
        }
        release {
            signingConfig = if (keyPropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // Enable R8 code shrinking with Firebase-safe ProGuard rules
            isMinifyEnabled = true
            isShrinkResources = true
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

    // Google Play Billing тянет плагин in_app_purchase_android (0.5.x = billing 8.x).
    // Свою версию сюда не прописывать: Play отклоняет обновления на библиотеке ниже 8.
}
