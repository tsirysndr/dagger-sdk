import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {execFileSync} from "node:child_process";
import {fileURLToPath} from "node:url";
const sdk=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
test("module scaffold creates a Spago workspace and preserves user edits",()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),"purescript-scaffold-"));
  try {
    fs.mkdirSync(path.join(directory,"dagger-sdk"));
    fs.copyFileSync(path.join(sdk,"spago.yaml"),path.join(directory,"dagger-sdk/spago.yaml"));
    const init=()=>execFileSync(process.execPath,[path.join(sdk,"scripts/init-module.mjs"),"hello-purescript"],{cwd:directory});
    init();
    assert.match(fs.readFileSync(path.join(directory,"src/Main.purs"),"utf8"),/Module.object_ "HelloPurescript"/);
    assert.doesNotMatch(fs.readFileSync(path.join(directory,"spago.yaml"),"utf8"),/extraPackages/);
    assert.doesNotMatch(fs.readFileSync(path.join(directory,"dagger-sdk/spago.yaml"),"utf8"),/^workspace:|^  test:/m);
    fs.appendFileSync(path.join(directory,"src/Main.purs"),"\n-- user edit\n");
    init();
    assert.match(fs.readFileSync(path.join(directory,"src/Main.purs"),"utf8"),/user edit/);
  } finally { fs.rmSync(directory,{recursive:true,force:true}); }
});
