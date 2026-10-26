import test from "node:test";
import assert from "node:assert/strict";
import { buildQuery, extract, connect, connectWith, requestImpl } from "../src/Dagger/Internal/Runtime.js";
import { inspectError } from "../src/Dagger/Errors.js";
const step = (name, args=[]) => ({name,args});
const arg = (name,typeName,value) => ({name,typeName,value});
const session = (timeoutMs=1000) => connectWith({port:12345,token:"secret",timeoutMs})();
const request = (s, steps) => new Promise((resolve,reject) => requestImpl(s)(steps)(e=>()=>reject(e))(v=>()=>resolve(v))());
async function mockFetch(fetch, action) {
  const original = globalThis.fetch;
  globalThis.fetch = fetch;
  try { return await action(); } finally { globalThis.fetch = original; }
}

test("values are variables: quotes, Unicode, false, zero, enums, nested inputs", () => {
  const value = 'héllo " \\ \n } mutation { bad }';
  const document = buildQuery([step("container"),step("from",[arg("address","String!",value)]),step("withExec",[arg("args","[String!]!",["echo",value]),arg("expand","Boolean",false),arg("expect","ReturnType","ANY")]),step("stdout")]);
  assert.equal(document.query,"query($v0: String!, $v1: [String!]!, $v2: Boolean, $v3: ReturnType) { container { from(address: $v0) { withExec(args: $v1, expand: $v2, expect: $v3) { stdout } } } }");
  assert.deepEqual(document.variables,{v0:value,v1:["echo",value],v2:false,v3:"ANY"});
  const input = [{name:"PORT",value:"0"}];
  assert.deepEqual(buildQuery([step("build",[arg("buildArgs","[BuildArg!]",input),arg("n","Int",0),arg("x","String",null)])]).variables,{v0:input,v1:0,v2:null});
});

test("selection extraction preserves JSON leaves, lists, and null", () => {
  const leaf={a:1,b:2};
  assert.equal(extract({value:leaf},[step("value")]),leaf);
  assert.deepEqual(extract({items:[{id:"a"},{id:"b"}]},[step("items"),step("id")]),["a","b"]);
  assert.equal(extract({node:null},[step("node"),step("... on Container"),step("id")]),null);
  assert.throws(()=>extract({},[step("missing")]),/missing/);
});

test("invalid query identifiers and session configuration fail early", () => {
  assert.throws(()=>buildQuery([]),/empty/);
  assert.throws(()=>buildQuery([step("x } mutation")]),/field/);
  assert.throws(()=>buildQuery([step("x",[arg("y","String!) { nope",1)])]),/argument/);
  for (const port of [0,-1,65536,1.5]) assert.throws(()=>connectWith({port,token:"x",timeoutMs:10})(),/port/);
  assert.throws(()=>connectWith({port:1234,token:"",timeoutMs:10})(),/token/);
  assert.throws(()=>connectWith({port:1234,token:"x",timeoutMs:0})(),/timeout/);
  const oldPort=process.env.DAGGER_SESSION_PORT, oldToken=process.env.DAGGER_SESSION_TOKEN;
  delete process.env.DAGGER_SESSION_PORT; delete process.env.DAGGER_SESSION_TOKEN;
  try { assert.throws(connect,/dagger api with-session/); } finally {
    if(oldPort!==undefined)process.env.DAGGER_SESSION_PORT=oldPort;
    if(oldToken!==undefined)process.env.DAGGER_SESSION_TOKEN=oldToken;
  }
});

test("transport sends POST, basic auth, variables, and disallows redirects", async () => {
  await mockFetch(async (url,options)=>{
    assert.equal(url,"http://127.0.0.1:12345/query");
    assert.equal(options.method,"POST");
    assert.equal(options.redirect,"error");
    assert.equal(options.headers.Authorization,`Basic ${Buffer.from("secret:").toString("base64")}`);
    assert.deepEqual(JSON.parse(options.body),{query:"query { version }",variables:{}});
    return new Response(JSON.stringify({data:{version:"v-test"}}));
  },async()=>assert.equal(await request(session(),[step("version")]),"v-test"));
});

test("GraphQL execution errors retain stdout, stderr, exit code and path", async () => {
  const extensions={_type:"EXEC_ERROR",cmd:["false"],exitCode:7,stdout:"out",stderr:"err"};
  await mockFetch(async()=>new Response(JSON.stringify({data:null,errors:[{message:"failed",path:["container","stdout"],extensions}]})), async()=>{
    await assert.rejects(request(session(),[step("stdout")]),error=>{
      assert.equal(error.name,"DaggerExecError");
      assert.deepEqual(inspectError(error).exec,{message:"failed",cmd:["false"],exitCode:7,stdout:"out",stderr:"err"});
      assert.deepEqual(error.errors[0].path,["container","stdout"]);
      return true;
    });
  });
});

test("non-execution GraphQL errors reject even with partial data", async () => {
  await mockFetch(async()=>new Response(JSON.stringify({data:{version:"partial"},errors:[{message:"broken"}]})),async()=>{
    await assert.rejects(request(session(),[step("version")]),{name:"DaggerGraphQLError",message:"broken"});
  });
});

test("HTTP, malformed JSON, absent data and wrong response shape reject", async () => {
  for (const response of [new Response("no",{status:503}),new Response("not-json"),new Response("{}"),new Response('{"data":{}}')]) {
    await mockFetch(async()=>response,async()=>assert.rejects(request(session(),[step("version")])));
  }
});

test("timeouts abort the in-flight request", async () => {
  await mockFetch((_url,options)=>new Promise((_resolve,reject)=>{
    options.signal.addEventListener("abort",()=>reject(options.signal.reason));
  }), async()=>assert.rejects(request(session(10),[step("version")]),/timed out/));
});

test("cancellation aborts fetch and never completes the Aff callback", async () => {
  let signal, called=false;
  await mockFetch((_url,options)=>new Promise((_resolve,reject)=>{
    signal=options.signal;
    signal.addEventListener("abort",()=>reject(signal.reason));
  }),async()=>{
    const cancel=requestImpl(session())([step("version")])(()=>()=>{called=true;})(()=>()=>{called=true;})();
    cancel();
    await new Promise(resolve=>setTimeout(resolve,15));
    assert.equal(signal.aborted,true);
    assert.equal(called,false);
  });
});
