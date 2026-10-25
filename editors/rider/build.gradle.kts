plugins {
    java
    id("org.jetbrains.intellij.platform") version "2.19.0"
}

group = "dev.zsharp"
version = "0.1.0"

repositories {
    mavenCentral()
    intellijPlatform { defaultRepositories() }
}

// JDK 25 reads 2026.x's class files; Java 21 bytecode still runs in 2025.2
java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }
tasks.withType<JavaCompile> { options.release = 21 }

dependencies {
    intellijPlatform {
        val local = providers.gradleProperty("platformPath")
        if (local.isPresent) local(local) else rider(providers.gradleProperty("platformVersion")) { useInstaller = false }
        bundledPlugin("org.jetbrains.plugins.textmate")
    }
}

intellijPlatform {
    buildSearchableOptions = false
    pluginConfiguration {
        ideaVersion { sinceBuild = "252"; untilBuild = provider { null } }
    }
}

// The highlighting is the VS Code extension's TextMate grammar and language configuration, shipped
// beside the plugin's jar (TextMate reads a bundle from a directory, not from inside a jar), in
// every sandbox: buildPlugin's and runIde's (prepareSandbox_runIde) alike.
tasks.withType<org.jetbrains.intellij.platform.gradle.tasks.PrepareSandboxTask>().configureEach {
    from("../vscode") {
        include("package.json", "language-configuration.json", "syntaxes/**")
        into(pluginName.map { "$it/textmate" })
    }
}

intellijPlatform {
    pluginVerification { ides { current() } }
}
