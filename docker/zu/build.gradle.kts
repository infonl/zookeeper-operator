import com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    // 1.9.25: the Kotlin 1.5.31 plugin bundled kotlin-stdlib 1.5.31 (CVE-2022-24329).
    kotlin("jvm") version "1.9.25"
    id("com.github.johnrengelman.shadow") version "7.1.2"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(kotlin("stdlib"))
    implementation("org.apache.zookeeper:zookeeper:3.9.5")
}

// zu.jar bundles (via shadowJar) only what the ZooKeeper *client* pulls onto the
// runtime classpath. In zookeeper's POM that is essentially Netty + slf4j +
// commons-io + audience-annotations. jackson / jetty / jline / snappy are
// `provided` scope and bouncycastle is `test` scope, so Gradle's `implementation`
// configuration does NOT bundle them here — those are only a concern for the
// server image's /lib and are handled in docker/zk-deps (see docker/Dockerfile).
//
// ZooKeeper 3.9.5 ships Netty 4.1.130.Final, which is affected by
// CVE-2026-33870 / CVE-2026-33871 / CVE-2026-45673 (and the 4.1.131/132
// request-smuggling + DoS fixes). Force every Netty module that can reach the
// classpath up to the latest 4.1.x. Keep this version identical to
// docker/zk-deps/pom.xml so the client and server never drift.
val nettyVersion = "4.1.137.Final"
configurations.all {
    resolutionStrategy {
        eachDependency {
            // netty-tcnative-* has its own (2.0.x) version line - leave it alone.
            if (requested.group == "io.netty" && !requested.name.contains("tcnative")) {
                useVersion(nettyVersion)
                because("CVE-2026-33870 / CVE-2026-33871 / CVE-2026-45673 - ZK 3.9.5 ships 4.1.130.Final")
            }
        }
    }
}

// Reproducible dependency resolution. Regenerate after any dependency change with:
//   ./gradlew --write-locks :dependencies      (or: make zu-lock)
// and commit docker/zu/gradle.lockfile. Trivy scans that lockfile in CI.
dependencyLocking {
    lockAllConfigurations()
    lockMode.set(LockMode.LENIENT)
}

tasks.withType<ShadowJar>() {
    classifier = null
    manifest {
        attributes["Main-Class"] = "io.pravega.zookeeper.MainKt"
    }
}

tasks.withType<KotlinCompile> {
  kotlinOptions {
    jvmTarget = "11"
  }
}
