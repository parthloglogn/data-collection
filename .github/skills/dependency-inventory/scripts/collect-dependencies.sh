#!/usr/bin/env bash

set -e

OUTPUT_DIR=".dependency-output"

mkdir -p "$OUTPUT_DIR"

echo "Detecting project type..."

# =========================
# Maven
# =========================
if [ -f "pom.xml" ]; then
    echo "Maven project detected"

    if [ -f "./mvnw" ]; then
        ./mvnw dependency:tree \
          -DoutputType=json \
          -DoutputFile="$OUTPUT_DIR/maven-dependencies.json"
    else
        mvn dependency:tree \
          -DoutputType=json \
          -DoutputFile="$OUTPUT_DIR/maven-dependencies.json"
    fi

    python3 .github/skills/dependency-inventory/scripts/normalize-maven.py \
      "$OUTPUT_DIR/maven-dependencies.json" \
      "$OUTPUT_DIR/dependency-inventory.json"

# =========================
# Gradle
# =========================
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "Gradle project detected"

    if [ -f "./gradlew" ]; then
        ./gradlew exportDependencies
    else
        gradle exportDependencies
    fi

    python3 .github/skills/dependency-inventory/scripts/normalize-gradle.py \
      "$OUTPUT_DIR/gradle-dependencies.json" \
      "$OUTPUT_DIR/dependency-inventory.json"

else
    echo "Unsupported build tool"
    exit 1
fi

echo "Dependency inventory generated:"
echo "$OUTPUT_DIR/dependency-inventory.json"