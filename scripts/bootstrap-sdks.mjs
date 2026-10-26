// Refresh the committed Go/Python bindings used by the SDK adapters.
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(path.join(tmpdir(), "dagger-bootstrap-"));
try {
  for (const sdk of ["purescript", "gleam", "clojure"]) {
    const doc = path.join(temporary, `${sdk}.graphql`);
    writeFileSync(doc, `{ moduleSource(refString: ${JSON.stringify(sdk)}) {
      generatedContextDirectory { directory(path: ${JSON.stringify(sdk)}) {
        export(path: ${JSON.stringify(sdk)})
      } }
    } }`);
    execFileSync(process.env.DAGGER_CLI_BIN ?? "dagger",
      ["api", "query", "-M", "--doc", doc], { cwd: root, stdio: "inherit" });
  }
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
