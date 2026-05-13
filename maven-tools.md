---
name: maven-tools
description: "JVM dependency intelligence via Maven Tools MCP server. Use when the user asks about Maven or Gradle dependencies, JVM library versions, safe upgrades, CVEs, license risks, release history, or project dependency health. Use when reviewing `pom.xml`, `build.gradle`, `build.gradle.kts`, or Maven coordinates. Use when the user says 'check my dependencies', 'should I upgrade X', or 'is this version safe'. Use even when the user just pastes a `groupId:artifactId` coordinate without a verb. Supports single-module and multi-module projects."
allowed-tools: mcp__maven-tools__* mcp__context7__* WebSearch WebFetch
---

# Maven Tools (Enhanced)

Use this skill to ground JVM dependency decisions in live Maven Central data.  
Supports **Maven** (`pom.xml`) and **Gradle** (`build.gradle` / `build.gradle.kts`), single-module and **multi-module** projects.  
Outputs a **Markdown table report** saved to the repo root as `dependency-audit-report.md`.

This is an execution skill. Use Maven Tools MCP first for dependency facts, then do the reasoning in-model. Assume Maven Tools MCP is already configured; only discuss setup if the tools are unavailable.

---

## When to Use

Activate when the user asks about:

- Java, Kotlin, Scala, or JVM dependencies
- Maven, Gradle, `pom.xml`, `build.gradle`, or `build.gradle.kts`
- latest versions, upgrades, CVEs, licenses, dependency age, or release history
- whether a dependency is safe, current, stale, or worth upgrading
- multi-module projects where each submodule may have its own dependency set

---

## Build File Detection

Before running any MCP tools, identify all build files in the repository:

### Maven
```
pom.xml                          ← root / single-module
module-a/pom.xml                 ← submodule
module-b/pom.xml                 ← submodule
```

### Gradle
```
build.gradle or build.gradle.kts         ← root / single-module
module-a/build.gradle(.kts)             ← submodule
module-b/build.gradle(.kts)             ← submodule
settings.gradle or settings.gradle.kts  ← lists all included submodules
```

**Multi-module detection rule:**  
- Maven: root `pom.xml` contains a `<modules>` block → each listed path has its own `pom.xml`.  
- Gradle: `settings.gradle` contains `include(...)` directives → each path has its own `build.gradle(.kts)`.

Always scan **every** module's build file. Do not stop at the root.

---

## Dependency Extraction by Build System

### Maven — from `pom.xml`
Extract all `<dependency>` entries under `<dependencies>` and managed versions from `<dependencyManagement>`.

Normalize each to: `groupId:artifactId:version`

### Gradle — from `build.gradle` or `build.gradle.kts`

**Groovy DSL** (`build.gradle`):
```groovy
dependencies {
    implementation 'com.google.guava:guava:32.1.3-jre'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.1'
}
```

**Kotlin DSL** (`build.gradle.kts`):
```kotlin
dependencies {
    implementation("com.google.guava:guava:32.1.3-jre")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.1")
}
```

Normalize each to: `groupId:artifactId:version`

**Version catalog** (`gradle/libs.versions.toml` — if present):
```toml
[versions]
guava = "32.1.3-jre"

[libraries]
guava = { module = "com.google.guava:guava", version.ref = "guava" }
```
Resolve all `version.ref` references before building the dependency list.

**BOM imports** (`platform(...)` in Gradle, `<scope>import</scope>` in Maven):  
Record the BOM coordinate and version. Treat BOM-managed versions as the effective version for child dependencies unless overridden.

---

## Core Boundary

Use Maven Tools MCP for version, security, license, freshness, and release-pattern facts from Maven Central.

- Do the reasoning in-model: recommend next steps, call out risk, and separate safe-now actions from manual-review items.
- Normalize dependency inputs to `groupId:artifactId` or `groupId:artifactId:version` as needed.
- For recommendation questions, evaluate concrete candidates with Maven Tools first, then add documentation context before making a strong call.
- Do not use Maven metadata alone to decide library popularity, framework fit, migration effort, or performance tradeoffs.

---

## Tool Selection

Choose the narrowest tool that matches the request:

| Intent | Tool | Default Parameters |
|--------|------|--------------------|
| Latest version lookup | `get_latest_version` | `stabilityFilter: PREFER_STABLE` |
| Check exact version | `check_version_exists` | none |
| Bulk candidate check (no current versions) | `check_multiple_dependencies` | `stabilityFilter: PREFER_STABLE` |
| Upgrade analysis (with current versions) | `compare_dependency_versions` | `includeSecurityScan: true`, `stabilityFilter: STABLE_ONLY` |
| Age / freshness | `analyze_dependency_age` | use project-appropriate threshold |
| Maintenance signal | `analyze_release_patterns` | `monthsToAnalyze: 24` |
| Release history | `get_version_timeline` | `versionCount: 20` |
| Full project audit | `analyze_project_health` | `includeSecurityScan: true`, `includeLicenseScan: true`, `stabilityFilter: PREFER_STABLE` |

Default to `analyze_project_health` when the user says "check my dependencies" or pastes a project dependency set.

Use `check_multiple_dependencies` for candidate sets without current versions.  
Use `compare_dependency_versions` for upgrade decisions on current versions.  
Use `analyze_project_health` for broad audits, not every single dependency question.

---

## Workflow

### Step 1 — Discover all modules

```
repo/
├── pom.xml  or  settings.gradle(.kts)     ← root
├── module-a/pom.xml  or  build.gradle(.kts)
├── module-b/pom.xml  or  build.gradle(.kts)
└── module-c/pom.xml  or  build.gradle(.kts)
```

List every module. For single-module projects, the list has one entry.

### Step 2 — Extract dependencies per module

For each module, produce a list: `groupId:artifactId:version`, tagged with scope  
(`compile`, `runtime`, `test`, `provided` for Maven; `implementation`, `testImplementation`, `compileOnly`, etc. for Gradle).

### Step 3 — Run MCP tools

- Use `analyze_project_health` per module for a full audit.
- Use `compare_dependency_versions` when the user asks about specific upgrade decisions.
- Aggregate results across all modules — deduplicate same coordinates that appear in multiple modules.

### Step 4 — Interpret results conservatively

- Patch and minor updates → safe now.
- Major updates → manual review unless user explicitly wants breaking upgrades.
- When `compare_dependency_versions` returns `same_major_stable_fallback`:
  - Surface both the major upgrade path and the fallback.
  - Recommend the fallback first for conservative maintenance.

### Step 5 — Write `dependency-audit-report.md` to the repo root

See **Report Format** section below.

---

## Report Format

Save the report as `dependency-audit-report.md` at the repository root.

````markdown
# Dependency Audit Report

**Project:** {project-name}  
**Build System:** Maven | Gradle (Groovy) | Gradle (Kotlin DSL)  
**Modules Scanned:** {N}  
**Date:** {YYYY-MM-DD}  
**Total Unique Dependencies:** {count}  

---

## Security Issues

| Module | Dependency | Current Version | CVE | Severity | Fixed In | Action |
|--------|-----------|----------------|-----|----------|----------|--------|
| module-a | log4j-core | 2.14.0 | CVE-2021-44228 | 🔴 Critical | 2.17.1 | Update immediately |
| root | jackson-databind | 2.13.0 | CVE-2022-42003 | 🟠 High | 2.14.0 | Update within days |

---

## Outdated Dependencies

### 🔴 Major Updates — Manual Review Required

| Module | Dependency | Current | Latest | Notes |
|--------|-----------|---------|--------|-------|
| module-b | slf4j-api | 1.7.36 | 2.0.9 | Breaking API changes; see migration guide |

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

## Version Conflicts (Multi-Module)

| Dependency | Versions Found | Modules | Resolution |
|-----------|---------------|---------|-----------|
| slf4j-api | 1.7.36, 2.0.9 | root, module-a | Pin to 2.0.9 in BOM / `dependencyManagement` |

---

## Unused / Undeclared Dependencies

| Module | Dependency | Issue |
|--------|-----------|-------|
| module-b | commons-io:2.11.0 | Declared but unused — consider removing |
| module-a | slf4j-api | Used but undeclared (transitive only) |

---

## Stale / Unmaintained Dependencies

| Module | Dependency | Current | Last Release | Months Since Release | Risk |
|--------|-----------|---------|-------------|---------------------|------|
| root | some-lib | 1.2.0 | 2021-03-01 | 38 | 🔴 High — no recent activity |

---

## License Risks

| Module | Dependency | Version | License | Risk |
|--------|-----------|---------|---------|------|
| module-c | some-gpl-lib | 2.0.0 | GPL-3.0 | 🔴 Review for distribution |

---

## Summary & Recommendations

| Priority | Action | Affected Modules |
|----------|--------|-----------------|
| 🔴 Immediate | Fix CVE-2021-44228 in log4j-core → 2.17.1 | module-a |
| 🔴 Immediate | Fix CVE-2022-42003 in jackson-databind → 2.14.0 | root |
| 🟡 This sprint | Apply minor/patch updates | root, module-a, module-c |
| 🟡 This sprint | Resolve slf4j version conflict | root, module-a |
| ⬜ Plan | Evaluate slf4j 2.x migration | module-b |
| ⬜ Plan | Remove unused commons-io | module-b |
````

**Severity legend used in all tables:**

| Symbol | Meaning |
|--------|---------|
| 🔴 | Critical / High — act immediately or within days |
| 🟠 | High |
| 🟡 | Medium / minor — act this sprint |
| 🟢 | Low / patch — safe, act at convenience |
| ⬜ | Informational / planned |

---

## Documentation Handoff

When the answer needs migration guides, API details, or library usage patterns, add documentation context before giving a strong recommendation.

Use this order:

1. Maven Tools MCP first for dependency facts
2. Raw Context7 tools if available in the current tool list
3. Standalone Context7 tools if available
4. `WebSearch` and `WebFetch` for official docs, release notes, and migration guides
5. If no documentation path is available, say dependency facts are available but deeper doc lookup is not

Use especially for: major upgrades, migration planning, recommendation-style comparisons between candidate libraries.

---

## Less Helpful / Out of Scope

- Private artifact repositories not mirrored through Maven Central
- Non-JVM ecosystems not using Maven coordinates
- Trivial one-off lookups where the exact dependency and decision are already obvious
- Recommendation questions driven mostly by ecosystem adoption or benchmarks unless docs and broader research are also added

---

## Setup Assumption

Assume Maven Tools MCP is already configured.

- `arvindand/maven-tools-mcp:latest` — when raw Context7 tools should be exposed through the same server
- `arvindand/maven-tools-mcp:latest-noc7` — when documentation is handled separately

Only discuss installation when the tools are unavailable.

---

## Recovery

| Issue | Action |
|-------|--------|
| MCP tools unavailable | Tell the user Maven Tools MCP is not configured and point them to <https://github.com/arvindand/maven-tools-mcp>. Mention `:latest` or `:latest-noc7`. |
| Gradle version catalog not resolved | Parse `gradle/libs.versions.toml` and resolve `version.ref` before proceeding. |
| BOM-managed version missing | Note the BOM coordinate; use the BOM's managed version as the effective version. |
| Dependency not found on Maven Central | Verify `groupId:artifactId` format. Note if the artifact appears to be internal/private. |
| Raw Context7 tools unavailable | Use standalone Context7 tools if available; otherwise fall back to `WebSearch` and `WebFetch`. |
| No documentation path available | Say dependency facts are available but deeper migration or API docs are not available in the current environment. |
| Security scan incomplete or slow | Use the partial result, say CVE data may be incomplete, and continue with version/maintenance guidance. |
| Version type unclear | Treat it as unstable and prefer a known stable release. |
| Multi-module — some modules have no dependencies | Include them in the report with a "No dependencies declared" note. |

---

> **License:** MIT  
> **Requires:** [Maven Tools MCP server](https://github.com/arvindand/maven-tools-mcp)  
> **Pairs with:** [context7 skill](../context7/) or standalone Context7 tools for documentation-heavy follow-up
