#!/usr/bin/env python3
"""Run a checked-in module example against the pinned Dagger engine."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("sdk", choices=("gleam", "purescript", "clojure"))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
dagger = shutil.which("dagger")
if not dagger:
    parser.error("Dagger is missing; run with mise exec -- python3 scripts/test-module.py <sdk>")
version = subprocess.check_output([dagger, "version"], text=True)
if "v1.0.0-beta.21" not in version:
    parser.error("This test requires Dagger v1.0.0-beta.21; use mise exec.")

# Copy the SDK into the temporary git context so local module sources remain
# inside the workspace on every platform, including hosted CI runners.
with tempfile.TemporaryDirectory(prefix=f"dagger-{args.sdk}-example-") as temp:
    workspace = Path(temp)
    shutil.copytree(repo / args.sdk, workspace / "sdk", ignore=shutil.ignore_patterns(
        "build", "node_modules", "output", ".spago", ".cpcache", "target", ".venv", "__pycache__", "examples"))
    subprocess.run(["git", "init", "--quiet", str(workspace)], check=True)

    def run(*arguments, cwd=workspace):
        return subprocess.check_output([dagger, *arguments],
                                       cwd=cwd, text=True, timeout=1200).strip()

    run("init")
    run("module", "install", "./sdk", "--name", args.sdk)
    name = f"hello-{args.sdk}"
    run("module", "init", args.sdk, "--name", name, "--path", f"./{name}", "-y")
    module = workspace / name
    shutil.copytree(repo / args.sdk / "examples/module/src", module / "src", dirs_exist_ok=True)
    run("generate", "-y", cwd=module)
    greeting = run("api", "call", "-m", ".", "hello", "--name", "developer", cwd=module)
    assert greeting == "Hello, developer!", repr(greeting)
    function = "container" if args.sdk == "purescript" else "container-echo"
    output = run("api", "call", "-m", ".", function, "--message", "module works", "stdout", cwd=module)
    assert output == "module works", repr(output)
    print(f"{args.sdk}: greeting and container module examples passed")
