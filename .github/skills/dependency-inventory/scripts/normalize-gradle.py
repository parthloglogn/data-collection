import json
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file) as f:
    data = json.load(f)

normalized = {
    "buildTool": "gradle",
    "dependencies": []
}

for dep in data.get("dependencies", []):
    normalized["dependencies"].append({
        "group": dep.get("group"),
        "artifact": dep.get("artifact"),
        "version": dep.get("version"),
        "scope": "runtime",
        "transitive": dep.get("transitive", True)
    })

with open(output_file, "w") as f:
    json.dump(normalized, f, indent=2)