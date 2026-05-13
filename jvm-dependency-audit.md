---
name: jvm-dependency-audit
description: "Combined JVM dependency audit skill for Maven and Gradle projects. Use when the user asks to check, audit, or review dependencies; says 'outdated deps', 'check my pom', 'check my build.gradle', or 'is this version safe'; pastes a groupId:artifactId coordinate; or wants a dependency health report before a release or during maintenance. Supports single-module and multi-module repos. Uses Maven Tools MCP for live Maven Central data and writes a two-table Markdown report (dependency-audit-report.md) to the repo root."
allowed-tools: mcp__maven-tools__* mcp__context7__* WebSearch WebFetch
---

# JVM Dependency Audit — Combined Skill

Unified audit skill for **Maven** (`pom.xml`) and **Gradle** (`build.gradle` / `build.gradle.kts`) projects, single-module and multi-module.

Uses Maven Tools MCP for live Maven Central data (versions, CVEs, licenses, freshness).  
Outputs exactly **two Markdown tables** written to `dependency-audit-report.md` at the repository root.

---

## When to Use

- "Check my dependencies" / "audit dependencies" / "outdated deps"
- Before a release or during regular maintenance
- After a security advisory
- User pastes a `pom.xml`, `build.gradle`, or `groupId:artifactId` coordinate
- Multi-module repo where submodules may diverge in dependency versions

---

## Phase 0 — Detect Build System & Discover All Modules

Run this before any other step. Never stop at the root.

### Maven

```bash
find . -name "pom.xml" | sort
```

A root `pom.xml` with a `<modules>` block is multi-module.  
Each `<module>` entry is a subdirectory with its own `pom.xml`.

### Gradle

```bash
find . \( -name "settings.gradle" -o -name "settings.gradle.kts" \) | sort
find . \( -name "build.gradle" -o -name "build.gradle.kts" \) | sort
```

Read `settings.gradle(.kts)` for the canonical module list:

```groovy
// Groovy DSL
include 'module-a', 'module-b', 'module-c'
```
```kotlin
// Kotlin DSL
include("module-a", "module-b", "module-c")
```

Check for a version catalog:
```bash
cat gradle/libs.versions.toml    # resolve all version.ref entries before extraction
```

**Single-module projects:** treat the root as the only module. The `Module` column in both report tables will show the project name or `root`.

---

## Phase 1 — Extract Dependencies per Module

### Maven — from each `pom.xml`

Extract every `<dependency>` under `<dependencies>`.  
Resolve overrides from `<dependencyManagement>`.  
Record BOM imports (`<scope>import</scope>`) as the effective version source for child dependencies.

Normalize to: `groupId | artifactId | version | scope`

**Direct vs transitive:**  
- Declared in the module's own `<dependencies>` block → **Direct**  
- Pulled in by another dependency → **Transitive**  

```bash
# Get the full resolved tree (shows transitive deps)
mvn dependency:tree -DoutputType=text

# Per module
mvn dependency:tree -pl module-a -DoutputType=text
```

### Gradle — from each `build.gradle` / `build.gradle.kts`

**Groovy DSL:**
```groovy
dependencies {
    implementation      'com.google.guava:guava:32.1.3-jre'
    testImplementation  'org.junit.jupiter:junit-jupiter:5.10.1'
    compileOnly         'org.projectlombok:lombok:1.18.30'
    runtimeOnly         'org.postgresql:postgresql:42.6.0'
}
```

**Kotlin DSL:**
```kotlin
dependencies {
    implementation("com.google.guava:guava:32.1.3-jre")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.1")
}
```

**Version catalog** (`gradle/libs.versions.toml`):
```toml
[versions]
guava = "32.1.3-jre"

[libraries]
guava = { module = "com.google.guava:guava", version.ref = "guava" }
```
Resolve all `version.ref` entries to concrete versions before building the list.

**BOM / platform imports:**
```groovy
implementation platform('org.springframework.boot:spring-boot-dependencies:3.2.0')
```
Record the BOM coordinate and version. Use BOM-managed versions as the effective version for child dependencies unless overridden.

**Direct vs transitive:**  
- Declared in the module's own `dependencies { }` block → **Direct**  
- Resolved transitively at runtime → **Transitive**  

```bash
# Full resolved tree per module and configuration
./gradlew :module-a:dependencies --configuration compileClasspath
./gradlew :module-a:dependencies --configuration testCompileClasspath

# Why is a specific library included?
./gradlew :module-a:dependencyInsight --dependency slf4j-api --configuration compileClasspath
```

---

## Phase 2 — Run Maven Tools MCP

Choose the narrowest tool that matches the request:

| Intent | Tool | Default Parameters |
|--------|------|--------------------|
| Full project audit | `analyze_project_health` | `includeSecurityScan: true`, `includeLicenseScan: true`, `stabilityFilter: PREFER_STABLE` |
| Upgrade analysis (current versions known) | `compare_dependency_versions` | `includeSecurityScan: true`, `stabilityFilter: STABLE_ONLY` |
| Bulk latest-version check (no current versions) | `check_multiple_dependencies` | `stabilityFilter: PREFER_STABLE` |
| Latest version lookup | `get_latest_version` | `stabilityFilter: PREFER_STABLE` |
| Age / freshness | `analyze_dependency_age` | project-appropriate threshold |
| Maintenance signal | `analyze_release_patterns` | `monthsToAnalyze: 24` |

- Default to `analyze_project_health` for a broad audit of each module.
- Run per module, then aggregate results across all modules.
- Deduplicate the same `groupId:artifactId` that appears in multiple modules — keep the per-module row in the tables; do not collapse across modules.

**Interpret conservatively:**
- Patch and minor updates → safe now.
- Major updates → manual review unless the user explicitly wants breaking upgrades.
- When `compare_dependency_versions` returns `same_major_stable_fallback`: surface both the major upgrade path and the fallback; recommend the fallback first.

---

## Phase 3 — Write `dependency-audit-report.md`

Save the file to the **repository root**.  
The report contains exactly **two tables** and a short header. Nothing else.

---

### Report Template

````markdown
# Dependency Audit Report

**Project:** {project-name}
**Build System:** Maven | Gradle (Groovy DSL) | Gradle (Kotlin DSL)
**Modules Scanned:** {N} — {module-a, module-b, module-c, ...}
**Date:** {YYYY-MM-DD}
**Total Dependencies:** {total rows in Table 1}
**Vulnerable Dependencies:** {total rows in Table 2}

---

## Table 1 — All Dependencies

> Lists every resolved dependency across all modules.
> For single-module projects the Module column shows the project name or `root`.
> Direct = declared in the module's own build file. Transitive = pulled in by another dependency.

| Module | Group ID | Artifact ID | Version | Direct / Transitive |
|--------|----------|-------------|---------|---------------------|
| root | org.springframework.boot | spring-boot-starter-web | 3.2.0 | Direct |
| root | org.springframework | spring-core | 6.1.2 | Transitive |
| root | com.fasterxml.jackson.core | jackson-databind | 2.13.0 | Transitive |
| module-a | com.google.guava | guava | 32.0.1-jre | Direct |
| module-a | org.slf4j | slf4j-api | 1.7.36 | Transitive |
| module-b | org.junit.jupiter | junit-jupiter | 5.9.0 | Direct |
| module-b | org.apache.logging.log4j | log4j-core | 2.14.0 | Direct |

_Sort order: Module → Direct before Transitive → Group ID alphabetically._

---

## Table 2 — Vulnerable Dependencies (Upgrade Required)

> Lists only dependencies with known CVEs or available upgrades that fix security issues.
> Severity follows CVSS: 🔴 Critical (9–10) | 🟠 High (7–8.9) | 🟡 Medium (4–6.9) | 🟢 Low (0.1–3.9).
> CVE Count = total known CVEs affecting the current version.
> Upgrade To = lowest version that resolves all listed CVEs.

| Module | Group ID | Artifact ID | Current Version | Direct / Transitive | Severity | CVE Count | Upgrade To |
|--------|----------|-------------|----------------|---------------------|----------|-----------|------------|
| module-b | org.apache.logging.log4j | log4j-core | 2.14.0 | Direct | 🔴 Critical | 3 | 2.17.1 |
| root | com.fasterxml.jackson.core | jackson-databind | 2.13.0 | Transitive | 🟠 High | 2 | 2.14.0 |
| module-a | org.slf4j | slf4j-api | 1.7.36 | Transitive | 🟡 Medium | 1 | 2.0.9 |

_If no vulnerabilities are found, write:_ `_No vulnerable dependencies detected._`
````

---

### Column rules

**Table 1 — All Dependencies**

| Column | Value |
|--------|-------|
| Module | Module name from `settings.gradle` or `<module>` tag. Use project name / `root` for single-module. |
| Group ID | Maven `groupId` exactly as declared or resolved. |
| Artifact ID | Maven `artifactId` exactly as declared or resolved. |
| Version | Effective resolved version (after BOM / conflict resolution). |
| Direct / Transitive | `Direct` if declared in this module's own build file; `Transitive` otherwise. |

**Table 2 — Vulnerable Dependencies**

| Column | Value |
|--------|-------|
| Module | Same as Table 1. |
| Group ID | Same as Table 1. |
| Artifact ID | Same as Table 1. |
| Current Version | Effective resolved version currently in use. |
| Direct / Transitive | Same as Table 1. |
| Severity | Highest CVSS severity across all CVEs for this version. Use emoji + label. |
| CVE Count | Total number of known CVEs affecting the current version. |
| Upgrade To | Lowest available stable version that resolves all CVEs. If no fix exists, write `No fix available`. |

**Sort order for both tables:** Module name → Direct before Transitive → Group ID alphabetically.

---

## Phase 4 — Documentation Handoff (for upgrade questions)

When the report surfaces major upgrades or migration-heavy changes, add documentation context before recommending action.

Order of preference:
1. Maven Tools MCP for dependency facts (already done in Phase 2)
2. Raw Context7 tools if available
3. Standalone Context7 tools if available
4. `WebSearch` + `WebFetch` for official docs, release notes, migration guides
5. If no documentation path is available, state that dependency facts are ready but deeper docs are unavailable in this environment

Use especially for: major version upgrades, BOM migrations, framework platform changes.

---

## Quick Commands Reference

| Task | Maven | Gradle |
|------|-------|--------|
| Find all build files | `find . -name "pom.xml"` | `find . -name "build.gradle*"` |
| Full dependency tree | `mvn dependency:tree` | `./gradlew :module:dependencies` |
| Resolved tree (specific config) | `mvn dependency:tree -pl module-a` | `./gradlew :module-a:dependencies --configuration compileClasspath` |
| Why is X included? | `mvn dependency:tree -Dincludes=groupId` | `./gradlew :module:dependencyInsight --dependency X` |
| Outdated versions | `mvn versions:display-dependency-updates` | `./gradlew dependencyUpdates` |
| Security scan | `mvn dependency-check:check` | `./gradlew dependencyCheckAnalyze` |
| Unused / undeclared | `mvn dependency:analyze` | (use OWASP or Snyk) |

---

## Recovery

| Issue | Action |
|-------|--------|
| MCP tools unavailable | Tell the user Maven Tools MCP is not configured; point to <https://github.com/arvindand/maven-tools-mcp>. Use `:latest` for bundled Context7, `:latest-noc7` otherwise. |
| Gradle version catalog not resolved | Parse `gradle/libs.versions.toml`; resolve all `version.ref` entries before proceeding. |
| BOM-managed version missing | Record the BOM coordinate; use its managed version as the effective version. |
| Dependency not found on Maven Central | Verify `groupId:artifactId` format; note if the artifact appears to be internal/private. |
| Security scan incomplete or slow | Use partial results; note CVE data may be incomplete; continue with version guidance. |
| Version type unclear | Treat as unstable; prefer the nearest known stable release. |
| Module has no dependencies | Include it in Table 1 with a single row: all dependency columns empty, a note `No dependencies declared`. Omit from Table 2. |
| Same dependency in multiple modules | Keep a separate row per module in both tables. Do not collapse across modules. |
| Context7 / docs tools unavailable | State dependency facts are ready but migration docs are unavailable; fall back to `WebSearch` / `WebFetch`. |

---

> **License:** MIT
> **Requires:** [Maven Tools MCP server](https://github.com/arvindand/maven-tools-mcp)
> **Pairs with:** Context7 or WebSearch/WebFetch for migration documentation
