---
name: maven-dependency-audit
description: "Audit Maven or Gradle JVM dependencies for outdated versions, security vulnerabilities, and conflicts. Supports single-module and multi-module projects. Use when user says 'check dependencies', 'audit dependencies', 'outdated deps', before releases, or during regular maintenance. Scans every module's pom.xml / build.gradle(.kts) and writes a Markdown table report to the repo."
---

# Maven / Gradle Dependency Audit Skill (Enhanced)

Audit JVM dependencies across **Maven** and **Gradle** projects — single-module and **multi-module** — for outdated versions, security vulnerabilities, conflicts, and unused declarations.  
Outputs a **Markdown table report** (`dependency-audit-report.md`) saved to the repository root.

---

## When to Use

- User says "check dependencies" / "audit dependencies" / "outdated dependencies"
- Before a release
- Regular maintenance (monthly recommended)
- After a security advisory
- Multi-module repo where each submodule may diverge in dependency versions

---

## Phase 0 — Detect Build System & Module Layout

Before running any commands, identify the build system and all modules.

### Maven

```bash
# Find all pom.xml files in the repo
find . -name "pom.xml" | sort
```

A root `pom.xml` that contains `<modules>` is a multi-module project.  
Each `<module>` entry maps to a subdirectory with its own `pom.xml`.

### Gradle

```bash
# Find root settings file and all build files
find . -name "settings.gradle" -o -name "settings.gradle.kts" | sort
find . -name "build.gradle" -o -name "build.gradle.kts" | sort
```

Read `settings.gradle(.kts)` to get the canonical module list:

```groovy
// Groovy DSL
include 'module-a', 'module-b', 'module-c'

// Kotlin DSL
include("module-a", "module-b", "module-c")
```

Check for a version catalog:
```bash
cat gradle/libs.versions.toml   # if present, resolve version.ref entries before extraction
```

**Rule:** Always scan every module. Never stop at the root.

---

## Phase 1 — Extract Dependencies per Module

### Maven

```bash
# From repo root — lists effective dependencies for every module
mvn dependency:tree -DoutputType=text
```

To target a specific module:
```bash
mvn dependency:tree -pl module-a -DoutputType=text
```

Extract `<dependency>` blocks from each `pom.xml`. Resolve any `<dependencyManagement>` overrides.  
Normalize each to: `groupId:artifactId:version:scope`

### Gradle (Groovy DSL)

```groovy
// build.gradle
dependencies {
    implementation      'com.google.guava:guava:32.1.3-jre'
    testImplementation  'org.junit.jupiter:junit-jupiter:5.10.1'
    compileOnly         'org.projectlombok:lombok:1.18.30'
    runtimeOnly         'org.postgresql:postgresql:42.6.0'
}
```

```bash
# Print resolved dependency tree per module
./gradlew :module-a:dependencies --configuration compileClasspath
./gradlew :module-a:dependencies --configuration testCompileClasspath
```

### Gradle (Kotlin DSL)

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.google.guava:guava:32.1.3-jre")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.1")
}
```

Same Gradle commands apply — replace module name as needed.

### Version Catalog (`gradle/libs.versions.toml`)

```toml
[versions]
guava    = "32.1.3-jre"
junit    = "5.10.1"

[libraries]
guava    = { module = "com.google.guava:guava",            version.ref = "guava" }
junit    = { module = "org.junit.jupiter:junit-jupiter",   version.ref = "junit" }
```

Resolve all `version.ref` entries before building the dependency list. Record the catalog file as the authoritative version source for those libraries.

### BOM / Platform Imports

**Maven:**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-dependencies</artifactId>
    <version>3.2.0</version>
    <type>pom</type>
    <scope>import</scope>
</dependency>
```

**Gradle:**
```groovy
implementation platform('org.springframework.boot:spring-boot-dependencies:3.2.0')
```

Record each BOM coordinate and version. Treat BOM-managed versions as the effective version for child dependencies unless a module overrides them explicitly.

---

## Phase 2 — Check for Outdated Dependencies

### Maven

```bash
# All modules from root
mvn versions:display-dependency-updates

# Quiet output (less verbose)
mvn versions:display-dependency-updates -q

# Single module
mvn versions:display-dependency-updates -pl module-a

# Plugin updates too
mvn versions:display-plugin-updates
```

### Gradle

```bash
# Using gradle-versions-plugin (add if not present — see below)
./gradlew dependencyUpdates

# Per module
./gradlew :module-a:dependencyUpdates
```

**Add the plugin** if not present (`build.gradle`):
```groovy
plugins {
    id 'com.github.ben-manes.versions' version '0.51.0'
}
```

Or Kotlin DSL (`build.gradle.kts`):
```kotlin
plugins {
    id("com.github.ben-manes.versions") version "0.51.0"
}
```

### Categorize Updates

| Category | Criteria | Action |
|----------|----------|--------|
| 🔴 Security | CVE fix in newer version | Update immediately |
| 🔴 Major | `x.0.0` change | Review changelog, test thoroughly |
| 🟡 Minor | `x.y.0` change | Usually safe, test |
| 🟢 Patch | `x.y.z` change | Safe, minimal testing |

---

## Phase 3 — Analyze Dependency Tree (Conflicts)

### Maven

```bash
# Full tree from root (all modules)
mvn dependency:tree

# Filter for a specific library
mvn dependency:tree -Dincludes=org.slf4j

# Analyze unused / undeclared
mvn dependency:analyze
```

**Conflict signals in Maven tree output:**

```
[INFO] +- com.example:module-a:jar:1.0:compile
[INFO] |  \- org.slf4j:slf4j-api:jar:1.7.36:compile
[INFO] +- com.example:module-b:jar:1.0:compile
[INFO] |  \- org.slf4j:slf4j-api:jar:2.0.9:compile (omitted for conflict)
```

- `(omitted for conflict)` — version conflict; Maven resolved it, but verify the winner is correct.
- `(omitted for duplicate)` — same version, no issue.

### Gradle

```bash
# Dependency tree per module
./gradlew :module-a:dependencies

# Filter for a specific configuration
./gradlew :module-a:dependencies --configuration compileClasspath

# Check for dependency insight (why is X included?)
./gradlew :module-a:dependencyInsight --dependency slf4j-api --configuration compileClasspath
```

**Cross-module version conflict detection (multi-module):**  
Compare the resolved versions of the same `groupId:artifactId` across all modules.  
Flag any case where the same library resolves to different versions in different modules.

---

## Phase 4 — Security Vulnerability Scan

### Option A: OWASP Dependency-Check (Recommended for both Maven and Gradle)

**Maven** — add plugin to root `pom.xml`:
```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>9.0.7</version>
</plugin>
```

```bash
mvn dependency-check:check
# Report: target/dependency-check-report.html
```

**Gradle** — add to root `build.gradle`:
```groovy
plugins {
    id 'org.owasp.dependencycheck' version '9.0.7'
}
```

```bash
./gradlew dependencyCheckAnalyze
# Report: build/reports/dependency-check-report.html
```

### Option B: GitHub Dependabot
Enable in repository Settings → Security → Dependabot alerts.  
Works for both Maven (`pom.xml`) and Gradle (`build.gradle`, `build.gradle.kts`, `gradle/libs.versions.toml`).

### Option C: Snyk CLI

```bash
snyk test --all-projects        # scans all modules (Maven + Gradle)
```

### Severity Reference

| CVSS Score | Severity | Action |
|------------|----------|--------|
| 9.0 – 10.0 | 🔴 Critical | Update immediately |
| 7.0 – 8.9 | 🟠 High | Update within days |
| 4.0 – 6.9 | 🟡 Medium | Update within weeks |
| 0.1 – 3.9 | 🟢 Low | Update at convenience |

---

## Phase 5 — Resolve Conflicts

### Maven — Pin via `dependencyManagement`

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
            <version>2.0.9</version>
        </dependency>
    </dependencies>
</dependencyManagement>
```

### Gradle — Force a version

```groovy
// Groovy DSL
configurations.all {
    resolutionStrategy {
        force 'org.slf4j:slf4j-api:2.0.9'
    }
}
```

```kotlin
// Kotlin DSL
configurations.all {
    resolutionStrategy {
        force("org.slf4j:slf4j-api:2.0.9")
    }
}
```

### Exclude Transitive Dependency

**Maven:**
```xml
<dependency>
    <groupId>com.example</groupId>
    <artifactId>some-library</artifactId>
    <version>1.0</version>
    <exclusions>
        <exclusion>
            <groupId>commons-logging</groupId>
            <artifactId>commons-logging</artifactId>
        </exclusion>
    </exclusions>
</dependency>
```

**Gradle:**
```groovy
implementation('com.example:some-library:1.0') {
    exclude group: 'commons-logging', module: 'commons-logging'
}
```

---

## Phase 6 — Generate `dependency-audit-report.md`

Write the following Markdown file to the **repository root** as `dependency-audit-report.md`.

````markdown
# Dependency Audit Report

**Project:** {project-name}  
**Build System:** Maven | Gradle (Groovy DSL) | Gradle (Kotlin DSL)  
**Modules Scanned:** {N} — {module-a, module-b, module-c, ...}  
**Date:** {YYYY-MM-DD}  
**Total Unique Dependencies:** {count}  

---

## Security Issues

| Module | Dependency | Current Version | CVE | Severity | Fixed In | Action |
|--------|-----------|----------------|-----|----------|----------|--------|
| module-a | log4j-core | 2.14.0 | CVE-2021-44228 | 🔴 Critical | 2.17.1 | Update immediately |
| root | jackson-databind | 2.13.0 | CVE-2022-42003 | 🟠 High | 2.14.0 | Update within days |

_No issues found_ — replace rows with this if the section is empty.

---

## Outdated Dependencies

### 🔴 Major Updates — Manual Review Required

| Module | Dependency | Current | Latest | Notes |
|--------|-----------|---------|--------|-------|
| module-b | slf4j-api | 1.7.36 | 2.0.9 | Breaking API changes; migration guide required |

### 🟡 Minor Updates — Safe with Testing

| Module | Dependency | Current | Latest |
|--------|-----------|---------|--------|
| root | junit-jupiter | 5.9.0 | 5.10.1 |
| module-a | guava | 32.0.1 | 32.1.3 |

### 🟢 Patch Updates — Safe

| Module | Dependency | Current | Latest |
|--------|-----------|---------|--------|
| module-c | commons-lang3 | 3.12.0 | 3.13.0 |

---

## Version Conflicts Across Modules

| Dependency | Versions Found | Modules Affected | Recommended Fix |
|-----------|---------------|-----------------|-----------------|
| slf4j-api | 1.7.36, 2.0.9 | root, module-a | Pin 2.0.9 in BOM / `dependencyManagement` / `resolutionStrategy` |

---

## Unused / Undeclared Dependencies

| Module | Dependency | Issue | Recommendation |
|--------|-----------|-------|----------------|
| module-b | commons-io:2.11.0 | Declared but unused | Remove from build file |
| module-a | slf4j-api | Used but undeclared (transitive only) | Declare explicitly |

---

## Stale / Unmaintained Dependencies

| Module | Dependency | Current | Last Release | Months Stale | Risk |
|--------|-----------|---------|-------------|-------------|------|
| root | some-old-lib | 1.2.0 | 2021-03-01 | 38 | 🔴 No recent activity |

---

## License Risks

| Module | Dependency | Version | License | Risk |
|--------|-----------|---------|---------|------|
| module-c | some-gpl-lib | 2.0.0 | GPL-3.0 | 🔴 Review before distribution |

---

## Per-Module Summary

| Module | Total Deps | Critical CVEs | High CVEs | Major Outdated | Minor/Patch Outdated | Conflicts | Status |
|--------|-----------|--------------|----------|---------------|---------------------|-----------|--------|
| root | 12 | 0 | 1 | 0 | 3 | 1 | 🟡 Action needed |
| module-a | 8 | 1 | 0 | 0 | 1 | 1 | 🔴 Critical |
| module-b | 5 | 0 | 0 | 1 | 0 | 0 | 🟡 Review |
| module-c | 4 | 0 | 0 | 0 | 1 | 0 | 🟢 OK |
| **Total** | **29** | **1** | **1** | **1** | **5** | **2** | — |

---

## Prioritised Recommendations

| Priority | Action | Module(s) | Effort |
|----------|--------|-----------|--------|
| 🔴 Immediate | Update log4j-core 2.14.0 → 2.17.1 (CVE-2021-44228) | module-a | Low |
| 🔴 Immediate | Update jackson-databind 2.13.0 → 2.14.0 (CVE-2022-42003) | root | Low |
| 🟡 This sprint | Apply 5 minor/patch updates | root, module-a, module-c | Low |
| 🟡 This sprint | Pin slf4j-api to 2.0.9 to resolve cross-module conflict | root, module-a | Low |
| ⬜ Plan | Evaluate slf4j 1.x → 2.x migration | module-b | Medium |
| ⬜ Plan | Remove unused commons-io | module-b | Low |
| ⬜ Plan | Replace or fork some-old-lib (38 months unmaintained) | root | High |
````

---

## Quick Commands Reference

| Task | Maven | Gradle |
|------|-------|--------|
| List all build files | `find . -name "pom.xml"` | `find . -name "build.gradle*"` |
| Outdated deps | `mvn versions:display-dependency-updates` | `./gradlew dependencyUpdates` |
| Outdated plugins | `mvn versions:display-plugin-updates` | `./gradlew dependencyUpdates` |
| Dependency tree | `mvn dependency:tree` | `./gradlew :module:dependencies` |
| Find specific dep | `mvn dependency:tree -Dincludes=groupId` | `./gradlew :module:dependencyInsight --dependency X` |
| Unused / undeclared | `mvn dependency:analyze` | (no built-in; use OWASP or Snyk) |
| Security scan | `mvn dependency-check:check` | `./gradlew dependencyCheckAnalyze` |
| Update all (CAUTION) | `mvn versions:use-latest-releases` | manual edits or Renovate bot |
| Resolve conflict | `<dependencyManagement>` block | `resolutionStrategy { force ... }` |

---

## Update Strategies

### Conservative (Recommended for Production)
1. Apply patch updates freely.
2. Apply minor updates with basic testing.
3. Treat major updates as a planned migration with changelog review.

### Selective
```bash
# Maven — update only one dependency
mvn versions:use-latest-versions -Dincludes=org.junit.jupiter

# Gradle — edit build file or version catalog directly, then verify
./gradlew :module:dependencies --configuration compileClasspath
```

### Automated (CI-friendly)
- **Renovate Bot** — supports Maven, Gradle, and version catalogs out of the box.
- **GitHub Dependabot** — supports `pom.xml`, `build.gradle`, `build.gradle.kts`, `libs.versions.toml`.

---

## Token Optimization Notes

- Use `-q` (quiet) flag on Maven commands for less verbose output.
- Use `--configuration compileClasspath` on Gradle to limit tree size.
- Filter with `-Dincludes=groupId:artifactId` or `--dependency` when looking for a specific library.
- Do not paste entire dependency trees into the report — summarize conflicts and flag anomalies only.
