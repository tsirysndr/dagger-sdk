import assert from "node:assert/strict";
let context, returned, seen;
export const setCall = parentName => name => parent => () => { context = {parentName,name,parent}; };
export const verifyResult = expected => () => assert.equal(returned,expected);
export const verifyRegistration = () => {
  assert.ok(seen.some(q=>q.includes("withConstructor")));
  assert.ok(seen.some(q=>q.includes("withFunction")));
  assert.ok(seen.some(q=>q.includes("withArg")));
  assert.ok(seen.some(q=>q.includes("withOptional")));
};
export const installMock = () => {
  seen = [];
  context = {};
  const previous = globalThis.fetch;
  globalThis.fetch = async (_url, options) => {
    const {query,variables} = JSON.parse(options.body);
    seen.push(query);
    // These SDK requests select a single path. Reconstruct a response tree
    // independently of the SDK's extractor, retaining fragments only as types.
    const fields = query.slice(query.indexOf("{"))
      .replace(/\([^)]*\)/g, "").replace(/\.\.\. on \w+/g, "")
      .match(/\b[_A-Za-z]\w*\b/g);
    const leaf = fields.at(-1);
    let value = "test-id";
    if (leaf === "parentName" || leaf === "parent" || leaf === "name" && fields[0] === "currentFunctionCall") value = context[leaf];
    if (leaf === "id" && fields.includes("inputArgs")) value = [{id:"arg-id"}];
    if (fields.includes("inputArgs")) {
      return new Response(JSON.stringify({data:{currentFunctionCall:{inputArgs:[{id:"arg-id"}]}}}));
    }
    if (leaf === "name" && fields[0] === "node") value = "amount";
    if (leaf === "value" && fields[0] === "node") value = "2";
    if (leaf === "returnValue") { returned = Object.values(variables).at(-1); value = null; }
    if (leaf === "returnError") value = null;
    for (let i=fields.length-1; i>=0; i--) value = {[fields[i]]:value};
    return new Response(JSON.stringify({data:value}));
  };
  return () => { globalThis.fetch = previous; };
};
