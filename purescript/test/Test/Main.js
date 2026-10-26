import assert from "node:assert/strict";
let calls;
export const installMock = () => {
  calls = [];
  const previous = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, "http://127.0.0.1:12345/query");
    assert.equal(options.headers.Authorization, `Basic ${Buffer.from("test-token:").toString("base64")}`);
    const { query, variables } = JSON.parse(options.body);
    calls.push({ query, variables });
    let data;
    if (query.includes("withExec")) {
      assert.deepEqual(variables, { v0: "alpine:3.21", v1: ["cat"], v2: false, v3: "hello\n", v4: "ANY" });
      assert.match(query, /\$v4: ReturnType/);
      data = {container: {from: {withExec: {stdout:"hello\n"}}}};
    } else if (query.includes("withNewFile")) {
      data = {directory: {withNewFile: {id: "directory-id"}}};
    } else if (query.includes("withMountedDirectory")) {
      assert.equal(variables.v2, "directory-id");
      data = {container: {from: {withMountedDirectory: {stdout: "mounted"}}}};
    } else if (query.includes("envVariables")) {
      data = {container: {from: {envVariables: [{id:"env-id"}]}}};
    } else if (query.includes("envVariable")) {
      data = {container: {from: {envVariable: null}}};
    } else if (query.includes("... on EnvVariable")) {
      assert.equal(variables.v0,"env-id");
      data = {node: {name: "HOME"}};
    } else throw new Error(`Unexpected query ${query}`);
    return new Response(JSON.stringify({data}), {status:200});
  };
  return () => { globalThis.fetch = previous; };
};
export const verifyMock = () => {
  assert.equal(calls.length, 8);
  assert.equal(calls.filter(c=>c.query.includes("withNewFile")).length, 2);
  assert.deepEqual(calls[2], calls[4]);
};
