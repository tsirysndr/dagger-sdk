# Writing modules

A Gleam module exposes an explicit object definition. `mod.serve` handles one
Dagger invocation: schema registration, a constructor, or a function call. Dagger
starts a fresh process for each invocation; use serialized object state for
values that need to survive between calls.

## Multiple arguments

`argument.pair` combines independently typed arguments. Use `argument.map` to
convert nested tuples to your own record when a function has many parameters.

```gleam
mod.function(
  "repeat",
  argument.pair(
    argument.required("text", codec.string()),
    argument.optional("times", codec.int()),
  ),
  codec.string(),
  fn(_context, args) {
    let #(text, times) = args
    Ok(string.repeat(text, option.unwrap(times, 1)))
  },
)
```

Use `argument.none()` for functions without arguments. Add descriptions with
`argument.with_description`, `mod.describe`, and `mod.with_description`.
`argument.with_default(json_value)` declares a JSON default that Dagger supplies
when the argument is omitted; apply it to an individual argument before pairing.

## Containers, directories, files, and other engine objects

Each generated object module provides a typed `codec()`. Inputs decode ID strings
into lazy objects. Outputs evaluate the object's ID and return it to Dagger.

```gleam
mod.function(
  "list_files",
  argument.required("directory", directory.codec()),
  codec.list(codec.string()),
  fn(_context, directory) {
    directory.entries(directory)
    |> result.map_error(codec.SdkError)
  },
)
```

To return a container, choose `container.codec()` as the return codec and build
it with `context.client`. Dagger callers can then chain `stdout`, `export`, or
other container operations onto your function.

## Constructors and persisted state

Declare a codec for your state. Its JSON property names must match the exposed
fields. Both input and output use the same codec.

```gleam
fn counter_codec() -> codec.Codec(Int) {
  codec.object(
    "Counter",
    decode.at(["count"], decode.int),
    fn(count) { json.object([#("count", json.int(count))]) },
  )
}

fn counter() -> mod.Object {
  mod.object("Counter")
  |> mod.with_field("count", codec.int())
  |> mod.with_constructor(
    argument.required("start", codec.int()),
    counter_codec(),
    fn(_context, start) { Ok(start) },
  )
  |> mod.with_function(mod.function(
    "increment",
    argument.none(),
    counter_codec(),
    fn(context, _) {
      use count <- result.try(mod.parent(context, counter_codec()))
      Ok(count + 1)
    },
  ))
}
```

If `Counter` is the module's root, call `mod.serve(counter(), [])`. Additional
objects are registered with `mod.serve(root, [counter(), another_object()])`.
A function returning an additional object uses that object's state codec.
Objects without a constructor start with `{}`.

The examples above use `gleam/dynamic/decode`, `gleam/json`, `gleam/result`,
`dagger/mod`, `dagger/mod/argument`, and `dagger/mod/codec`.

## Errors

Handlers return `Result(value, codec.Error)`. Return
`Error(codec.FunctionError("Explain what failed"))` for your own failures.
Use `result.map_error(codec.SdkError)` to propagate SDK operation failures.
The scaffold asserts success at the process boundary, so failed invocations
exit with a diagnostic and a nonzero status.

## Testing

`mod.invoke` dispatches without an engine. Pass a `mod.Context` containing an
injected client and JSON parent state, and a dictionary of decoded argument
values. This tests real handler code and codecs without starting containers.

`mod.serve_with_client` additionally exercises the current-function-call and
return-value protocol. See [module_test.gleam](../test/module_test.gleam) for
constructors, state, object codecs, registration, and protocol tests.

The bootstrap SDK lives in [runtime](../runtime/src/main/__init__.py). It uses
Dagger's Python SDK to implement `codegen` and `module_runtime`; user code runs
as an Erlang shipment with `dagger_main` as its entrypoint. Existing project
configuration is checked rather than overwritten. The scaffold lives in
[runtime/template](../runtime/template/main.gleam).
