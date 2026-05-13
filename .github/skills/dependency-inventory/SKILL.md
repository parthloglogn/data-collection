---
name: Dependency Inventory
description: Detect and export Maven and Gradle dependencies into normalized JSON
---

# Dependency Inventory Skill

This skill detects Maven and Gradle projects and exports
their resolved dependencies into a normalized JSON format.

## Supported Build Tools

- Maven
- Gradle

## Workflow

1. Detect build tool
2. Execute dependency export
3. Normalize dependency output
4. Generate dependency-inventory.json

## Maven

Preferred command:

```bash
./mvnw dependency:tree \
  -DoutputType=json \
  -DoutputFile=dependency-tree.json
````

Fallback:

```bash
mvn dependency:tree \
  -DoutputType=json \
  -DoutputFile=dependency-tree.json
```

## Gradle

Preferred command:

```bash
./gradlew exportDependencies
```

Fallback:

```bash
gradle exportDependencies
```

## Final Output

Generate:

```txt
dependency-inventory.json
```

The output must follow the shared dependency schema.