import json
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file) as f:
    data = json.load(f)

dependencies = []

def walk(dep, transitive=False):
    dependencies.append({
        "group": dep.get("groupId"),
        "artifact": dep.get("artifactId"),
        "version": dep.get("version"),
        "scope": dep.get("scope"),
        "transitive": transitive
    })

    for child in dep.get("children", []):
        walk(child, True)

walk(data)

output = {
    "buildTool": "maven",
    "dependencies": dependencies
}

with open(output_file, "w") as f:
    json.dump(output, f, indent=2)