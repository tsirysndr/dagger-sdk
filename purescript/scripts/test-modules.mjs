import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
const sdk = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const directory = mkdtempSync(path.join(tmpdir(),"dagger-purescript-module-"));
function dagger(args) {
  return execFileSync("dagger",["--progress","plain",...args],{encoding:"utf8",stdio:["ignore","pipe","inherit"]}).trim();
}
try {
  dagger(["init","--name","purescript-smoke","--license","MIT","--sdk",sdk,directory]);
  assert.equal(dagger(["-m",directory,"call","hello","--name","developer"]),"Hello, developer!");
  assert.equal(dagger(["-m",directory,"call","container","--message","module works","stdout"]),"module works");
  console.log("PureScript module engine integration passed");
} finally {
  rmSync(directory,{recursive:true,force:true});
}
