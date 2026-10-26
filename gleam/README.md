# Dagger for Gleam

Build container pipelines and write **Dagger modules in Gleam**.

```gleam
dag
|> client.container
|> container.from("alpine:3.22")
|> container.with_exec(["echo", "Hello from Gleam!"])
|> container.stdout
// Result(String, dagger.Error)
```

Pipe-friendly functions, typed options, lazy objects, and explicit `Result` values.
The SDK targets **Erlang** and includes 715 generated API fields, a schema generator,
and a runtime for Gleam-authored Dagger modules.

**Status:** experimental. Compilation, unit tests, session lifecycle tests, and
mocked module protocol tests are covered. Live Docker/engine execution and the
bootstrap container still need verification in an environment with Docker and
network access. The checked-in API comes from the sibling Dagger repository's
schema fixture; module builds regenerate bindings from the actual engine schema.

## Requirements

- Gleam 1.14 or newer; tested locally with 1.19.2.
- Erlang/OTP 27 or newer (`json` and `inets` are used by the transport).
- Dagger CLI and a working engine for real pipelines.
- Python 3.12+ for SDK generation and the test fixtures.

Gleam module containers include their own compiler and Erlang runtime. You only
need the Dagger CLI and an engine to invoke them.

## Use the SDK in an application

This package has not been published to Hex. Add a local dependency to your
application's `gleam.toml`:

```toml
[dependencies]
dagger = { path = "../dagger-sdk/gleam" }
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
```

Then write a pipeline:

```gleam
import dagger
import dagger/client
import dagger/container
import gleam/io

pub fn main() {
  let result = dagger.with_connection(fn(dag) {
    dag
    |> client.container
    |> container.from("alpine:3.22")
    |> container.with_exec(["echo", "Hello from Gleam!"])
    |> container.stdout
  })

  case result {
    Ok(output) -> io.print(output)
    Error(error) -> echo error
  }
}
```

Run it with:

```sh
dagger run -- gleam run
```

`with_connection` closes sessions even when the callback fails or panics. Under
`dagger run`, it reuses `DAGGER_SESSION_PORT` and `DAGGER_SESSION_TOKEN` without
closing the parent session. Outside an existing session, `gleam run` starts
`dagger session` from `PATH`. Set `_EXPERIMENTAL_DAGGER_CLI_BIN` to select a binary.
The SDK does not download a CLI automatically.

For manual lifecycle control, use `dagger.connect()` and `dagger.close(client)`.
`dagger/connection.connect_with_timeout(milliseconds)` provides a configurable
startup/request timeout; wrap its result with `dagger.from_connection`.

## Write a Dagger module

Create a module using this directory as the custom SDK. Replace the absolute
path below with your checkout:

```sh
mkdir hello-gleam
cd hello-gleam
dagger init --name hello-gleam --sdk /absolute/path/to/dagger-sdk/gleam
dagger develop
dagger call hello --name Gleam
dagger call container-echo --message "Hello from a module" stdout
```

The SDK scaffolds `gleam.toml` and `src/dagger_main.gleam`. It generates a local
`dagger_sdk` dependency and compiles your code into an Erlang shipment. All
function invocation code runs in Gleam; a small Python SDK module supplies the
Dagger bootstrap hooks.

The generated module looks like this:

```gleam
import dagger/mod
import dagger/mod/argument
import dagger/mod/codec

pub fn main() {
  let assert Ok(_) = mod.serve(definition(), [])
}

pub fn definition() -> mod.Object {
  mod.object("HelloGleam")
  |> mod.with_function(mod.function(
    "hello",
    argument.required("name", codec.string()),
    codec.string(),
    fn(_context, name) { Ok("Hello, " <> name <> "!") },
  ))
}
```

The object name must match your Dagger module name in PascalCase. Function and
argument names are declared once. Their codecs drive both schema registration
and invocation, while Gleam checks the handler's argument and return types.

For an existing Gleam project, add `dagger = { path = "dagger_sdk" }` to
`[dependencies]` and provide `src/dagger_main.gleam`. Existing application source
and `gleam.toml` are preserved. The SDK owns `dagger_sdk/` and
`dagger_sdk_entrypoint.sh`; do not edit those generated files.

See [the module guide](docs/modules.md) for multiple arguments, engine objects,
constructors, persisted state, and testing.

## Options and object arguments

Common calls use defaults. Their `_with` variants accept typed option lists:

```gleam
container.with_exec_with(container, ["echo", "hello"], [
  container.WithExecUseEntrypoint(True),
  container.WithExecStdin("input"),
])
```

An omitted option leaves the engine default intact. If an option is repeated,
the last value wins. Enums live in their own modules, for example
`dagger/cache_sharing_mode.Locked`.

Object arguments accept objects directly:

```gleam
let source = dag |> client.directory

dag
|> client.container
|> container.from("alpine:3.22")
|> container.with_directory("/src", source)
|> container.with_exec(["ls", "/src"])
|> container.stdout
```

Object selections remain lazy. Terminal operations such as `stdout`, `entries`,
`id`, and `sync` execute requests. Referenced objects resolve to IDs at execution
time. `sync` returns the evaluated object in a `Result`, so use `result.try` to
continue a pipeline after it. Object lists reload their members by ID.

Object types can be imported from their modules, such as
`dagger/container.{type Container}`. Scalar wrappers and input records live in
`dagger/types`. `container.from_id` reloads a saved ID without an immediate request.
Nullable scalar/list results use `Option`; nullable object selections are lazy
and report unavailable values when a terminal field is requested.

## Errors and custom queries

`dagger/errors` distinguishes connection, transport, HTTP, GraphQL, JSON, and
result-decoding failures. GraphQL errors retain their message, path, and
extensions (including engine-specific execution details). Partial data is not
returned when the engine reports errors.

For an API field outside the generated snapshot, `dagger.execute(client,
 document, decoder)` executes a raw GraphQL document and decodes its `data` object.
`dagger/connection.with_transport` and `dagger.from_connection` let tests inject a
transport without an engine. See [the tests](test/dagger_test.gleam).

## Develop and test

Run these commands from this directory:

```sh
gleam deps download
gleam format --check src test runtime/template
gleam test
gleam export erlang-shipment
python3 -m unittest discover -s codegen -p 'test_*.py'
```

The default tests require Python for a fake CLI, but need neither Docker nor
network access. Tests cover lazy query execution, escaping, object arguments,
errors, session startup/timeout/cleanup, codecs, module registration, and dispatch.
The scaffold is also compiled as a test module.

Additional checks requiring local sockets or a real engine:

```sh
DAGGER_TEST_HTTP=1 gleam test
dagger run -- gleam run -m live_smoke
```

The HTTP check exercises authentication and `/query` against a local test server.
The smoke test runs Alpine through the actual engine. For module integration,
run the `dagger init` / `dagger call` walkthrough above.

## Update generated bindings

```sh
python3 codegen/generate.py codegen/schema.json
```

To use another schema, pass a standard introspection JSON file instead. The
generator accepts a schema object, `{"__schema": ...}`, or
`{"data": {"__schema": ...}}`. It formats output with `gleam format` and preserves
handwritten modules. Dagger module builds do this automatically using the
engine-provided introspection file, including dependencies.

Generated files are marked at the top. Make changes in `codegen/generate.py`,
then regenerate and run the tests. See [NOTICE](NOTICE) for snapshot provenance.

## Current scope

- Erlang target; no JavaScript transport.
- SDK client and custom Dagger module runtime, including primitives, nullable
  values, lists, engine objects, constructors, fields, and additional stateful objects.
- Module authoring uses explicit typed builders, not reflection or annotations.
- User-defined module enums, interfaces, and unions are not implemented yet.
- CLI provisioning, telemetry, and automatic retries are not implemented.

## License

The SDK implementation is [MIT licensed](LICENSE). The upstream schema and
schema-derived documentation retain their Apache-2.0 license; see [NOTICE](NOTICE)
and [the upstream license](codegen/UPSTREAM_LICENSE).
