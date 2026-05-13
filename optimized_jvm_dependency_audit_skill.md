# JVM Dependency Audit Skill (Optimized)

---
name: jvm-dependency-audit

description: >
  Audit Maven and Gradle dependencies for outdated versions,
  vulnerabilities, and dependency health. Supports single-module
  and multi-module JVM repositories.

allowed-tools:
  - mcp__maven-tools__*
  - mcp__context7__*
  - WebSearch
  - WebFetch
---

# Purpose

Use when the user asks to:
- audit dependencies
- check outdated dependencies
- review pom.xml or build.gradle
- check dependency vulnerabilities
- validate dependency health before release

Outputs:
- dependency-audit-report.md

---

# Phase 1 — Detect Build System

## Maven

Find all pom.xml files.

Multi-module Maven projects:
- root pom contains <modules>
- each module has its own pom.xml

## Gradle

Find:
- settings.gradle / settings.gradle.kts
- build.gradle / build.gradle.kts

Use settings.gradle(.kts) as the canonical module list.

If gradle/libs.versions.toml exists:
- resolve all version.ref entries
- use resolved versions during extraction

---

# Phase 2 — Extract Dependencies

Normalize all dependencies into:

groupId | artifactId | version | scope | module | dependencyType

Where:
- Direct = declared in module build file
- Transitive = resolved through another dependency

## Maven Rules

- extract all dependencies from pom.xml
- resolve dependencyManagement overrides
- resolve BOM-managed versions
- use effective resolved versions

## Gradle Rules

Support:
- Groovy DSL
- Kotlin DSL
- Version catalogs
- platform/BOM imports

Use effective resolved versions after BOM resolution.

---

# Phase 3 — Analyze Dependency Health

Preferred tool:
- analyze_project_health

Default settings:
- includeSecurityScan: true
- includeLicenseScan: true
- stabilityFilter: PREFER_STABLE

Additional tools when needed:
- compare_dependency_versions
- check_multiple_dependencies
- get_latest_version
- analyze_dependency_age
- analyze_release_patterns

Rules:
- prefer stable versions
- recommend patch/minor upgrades first
- flag major upgrades separately
- use lowest secure upgrade version
- keep separate rows per module

---

# Phase 4 — Generate Report

Write:
- dependency-audit-report.md

The report contains exactly two tables.

---

# Table 1 — All Dependencies

| Module | Group ID | Artifact ID | Version | Direct / Transitive |
|---|---|---|---|---|

Rules:
- use effective resolved version
- sort by:
  1. module
  2. direct before transitive
  3. groupId alphabetically

---

# Table 2 — Vulnerable Dependencies

| Module | Group ID | Artifact ID | Current Version | Direct / Transitive | Severity | CVE Count | Upgrade To |
|---|---|---|---|---|---|---|---|

Severity mapping:
- 🔴 Critical = 9.0–10
- 🟠 High = 7.0–8.9
- 🟡 Medium = 4.0–6.9
- 🟢 Low = 0.1–3.9

Rules:
- include only vulnerable dependencies
- use lowest stable fixed version
- if no fix exists:
  - Upgrade To = No fix available

If none exist:
- _No vulnerable dependencies detected._

---

# Special Handling

## BOM-managed dependencies

Use BOM-managed versions as effective versions.

## Multi-module projects

Keep separate rows per module.
Do not collapse duplicates.

## Empty modules

If a module has no dependencies:

| Module | Group ID | Artifact ID | Version | Direct / Transitive |
|---|---|---|---|---|
| module-name | | | | No dependencies declared |

---

# Output Requirements

- deterministic output
- no extra prose
- no summaries outside report
- no markdown explanations outside required tables
- always use effective resolved versions
- prefer stable upgrade recommendations

