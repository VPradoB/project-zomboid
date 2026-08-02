#!/usr/bin/env python3
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
required = (
    "-XX:+UseG1GC",
    "-Dsun.reflect.noInflation=true",
    "-Djdk.reflect.useDirectMethodHandle=false",
    "-XX:CompileCommand=exclude,java/lang/Class,reflectionData",
)

if not path.is_file():
    raise SystemExit(f"missing expected JSON: {path}")

try:
    data = json.loads(path.read_text())
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"cannot read {path}: {error}") from error

args = data.get("vmArgs")
if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
    raise SystemExit(f"missing string array 'vmArgs' in {path}")

normalized = []
for arg in args:
    arg = "-XX:+UseG1GC" if arg == "-XX:+UseZGC" else arg
    if arg not in required or arg not in normalized:
        normalized.append(arg)
normalized.extend(arg for arg in required if arg not in normalized)
data["vmArgs"] = normalized

temporary = path.with_suffix(path.suffix + ".tmp")
try:
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)
except OSError as error:
    raise SystemExit(f"cannot update {path}: {error}") from error
