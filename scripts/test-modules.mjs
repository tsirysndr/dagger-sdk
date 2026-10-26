// Live beta integration: scaffold, generate, and invoke modules in both languages.
import { execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspace = mkdtempSync(path.join(tmpdir(), "dagger-beta-modules-"));
const excluded = new Set([".git", ".spago", "output", "node_modules", "build", ".venv", "__pycache__"]);
function dagger(args, cwd = workspace) {
  return execFileSync(process.env.DAGGER_CLI_BIN ?? "dagger", args,
    { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();
}
try {
  dagger(["init"]);
  for (const sdk of ["gleam", "purescript"]) {
    cpSync(path.join(root, sdk), path.join(workspace, "sdks", sdk), {
      recursive: true, filter: source => !excluded.has(path.basename(source)),
    });
    dagger(["module", "install", `./sdks/${sdk}`, "--name", sdk]);
    dagger(["module", "init", sdk, "--name", `hello-${sdk}`, "--path", `./hello-${sdk}`, "-y"]);
    assert.equal(dagger(["api", "call", "-m", `./hello-${sdk}`, "hello", "--name", "developer"]), "Hello, developer!");
    const fn = sdk === "gleam" ? "container-echo" : "container";
    assert.equal(dagger(["api", "call", "-m", `./hello-${sdk}`, fn, "--message", "module works", "stdout"]), "module works");
  }
  const caller = path.join(workspace, "hello-purescript");
  dagger(["module", "client", "add", "../hello-gleam", "--sdk=purescript", "-y"], caller);
  writeFileSync(path.join(caller, "src/Main.purs"), `module Main where
import Prelude
import Dagger.HelloGleam as HelloGleam
import Dagger.Modules as Module
import Dagger.Query as Query
import Effect (Effect)
main :: Effect Unit
main = Module.runModule
  [ Module.object_ "HelloPurescript" {}
      [ Module.function "hello" "Call the Gleam module from PureScript."
          (Module.argument "name")
          (\\client name -> Query.helloGleam client # HelloGleam.hello name)
      ]
  ]
`);
  assert.equal(dagger(["api", "call", "-m", ".", "hello", "--name", "dependency"], caller), "Hello, dependency!");
  console.log("Gleam and PureScript beta module integration and dependency call passed");
} finally {
  rmSync(workspace, { recursive: true, force: true });
}
