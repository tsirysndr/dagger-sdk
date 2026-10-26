# Dagger for PureScript

Write Dagger pipelines **and Dagger modules** in PureScript.

- Pure, immutable builders composed with `#`.
- `Aff` at execution boundaries, with cancellation and timeouts.
- Distinct object types, custom scalar newtypes, enums, and `Maybe` results.
- Typed option records with defaults; object arguments resolve their IDs lazily.
- 696 generated API fields across 61 modules.
- Module registration and invocation, typed arguments, constructors, and stateful methods.

**Experimental.** The client and module protocol are tested locally against mock
transport, and the generated module template compiles independently. End-to-end
engine tests are included but have not been run in this development environment
because Docker socket access is restricted. See [status and limits](#status-and-limits).

## Get started

You need Node.js 22+, PureScript 0.15.16, and Spago 1.0.5. Dagger and a working
container engine are needed for real pipelines and module integration tests.

From this directory:

```sh
npm install
npm run build
npm test
```

The repository pins the PureScript package set in `spago.yaml` and dependency
resolution in `spago.lock`. The npm development tools are pinned in `package.json`.

Run the engine smoke test:

```sh
dagger run -- npm run test:integration
```

This runs a container, creates and reads a file, then mounts a directory into a
container. It is a small working pipeline you can copy from
[`test/Test/Integration.purs`](test/Test/Integration.purs).

### Use the client in your project

The SDK is not published to the PureScript registry yet. Add an external checkout
as a path dependency in your project's `spago.yaml`:

```yaml
package:
  name: my-pipeline
  dependencies:
    - aff
    - console
    - dagger-sdk
    - effect
    - prelude
workspace:
  packageSet:
    registry: 77.8.0
  extraPackages:
    dagger-sdk:
      path: ../dagger-sdk/purescript
```

The example assumes the SDK checkout is outside your project's workspace. When
vendoring a package *inside* a Spago workspace, use a package-only manifest for
that package and let Spago discover it; do not also list it under `extraPackages`.
The module bootstrap handles this for you.

Create `src/Main.purs`:

```purescript
module Main where

import Prelude
import Dagger (withConnection)
import Dagger.Container as Container
import Dagger.Query as Query
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)

main :: Effect Unit
main = launchAff_ $ withConnection \client -> do
  output <- Query.container client
    # Container.from "alpine:3.21"
    # Container.withExec [ "echo", "Hello from PureScript!" ]
    # Container.stdout
  liftEffect $ log output
```

```sh
dagger run -- spago run
```

`dagger run` supplies `DAGGER_SESSION_PORT` and `DAGGER_SESSION_TOKEN`. The CLI owns
the session; the SDK attaches to it. For an existing session you can also use
`Dagger.connectWith { port, token, timeoutMs }`.

## The client API

### Builders are pure; leaves execute

`Query.container`, `Container.from`, and `Container.withExec` construct immutable
query paths. `Container.stdout`, `File.contents`, and other scalar leaves return
`Aff`. Reusing a builder does not mutate it or cache its result.

Use qualified imports to keep names such as `id`, `file`, and `directory` clear.
Types and enum constructors live in `Dagger.Types`. Reserved PureScript words
receive a trailing underscore, for example `Query.module_` and `Container.import_`.

### Options use record updates

```purescript
import Data.Maybe (Maybe(..))
import Dagger.Types (ReturnType(..))

-- Inside your pipeline:
let opts = Container.defaultWithExecOpts
      { stdin = Just "hello\n"
      , expect = Just ReturnTypeAny
      , useEntrypoint = Just false
      }
output <- Query.container client
  # Container.from "alpine:3.21"
  # Container.withExecWith [ "cat" ] opts
  # Container.stdout
```

The short function uses engine defaults. The `With` variant accepts an options
record. `Nothing` omits an argument; `Just false`, `Just 0`, and empty arrays are
preserved. Nullable response values use `Maybe`.

### Pass Dagger objects directly

```purescript
import Dagger.Directory as Directory

let source = Query.directory client
      # Directory.withNewFile "hello.txt" "hello"

output <- Query.container client
  # Container.from "alpine:3.21"
  # Container.withMountedDirectory "/src" source
  # Container.withExec [ "cat", "/src/hello.txt" ]
  # Container.stdout
```

Object IDs are resolved when the request executes. Object-list results return
`Aff (Array ObjectType)`; each object can be used in subsequent typed selections.

### Errors

Use ordinary `Aff` error handling, or `Dagger.Errors.tryDagger` to obtain an
`Either DaggerError a`. Its constructors are:

- `ExecFailure`: command, exit code, stdout, stderr, and message.
- `GraphQLFailure`: the full list of GraphQL errors, including paths and extensions.
- `RequestFailure`: transport, timeout, configuration, or decoding failure messages.

Cancelling an `Aff` request aborts its HTTP fetch. Requests time out after five
minutes by default. Arguments are sent as GraphQL variables, never interpolated
into the query text. Authentication is sent only to the loopback session endpoint;
redirects are rejected.

For an API outside your generated bindings, `Dagger.Connection` exposes sessions
and `rawQuery`, which accepts a query string and Argonaut JSON variables.

## Write a Dagger module

The custom SDK is described by [`dagger.json`](dagger.json). Its small Go adapter
builds a Node.js/PureScript runtime, generates bindings from Dagger's supplied
schema, scaffolds a Spago package, and compiles your module. **Your module and its
registration/invocation runtime are PureScript.**

From a directory alongside this checkout, use the absolute path to `purescript`
as your custom SDK:

```sh
dagger init --name hello-purescript --license MIT \
  --sdk /absolute/path/to/dagger-sdk/purescript ./hello-purescript
cd hello-purescript
dagger call hello --name developer
dagger call container --message "Hello from a module!" stdout
```

The scaffold creates `src/Main.purs` with a greeting and a function returning a
Dagger container. You can inspect the exact template
[here](runtime/template/src/Main.purs). `Main.main` calls `Module.runModule`.

### Infer argument and return types from handlers

```purescript
module Main where

import Prelude
import Dagger.Modules as Module
import Effect (Effect)

main :: Effect Unit
main = Module.runModule
  [ Module.object_ "HelloPurescript" {}
      [ Module.function "greet" "Greet someone by name."
          (ado
            name <- Module.argument "name"
            greeting <- Module.defaultArgument "greeting" "Hello"
            in { name, greeting })
          (\_ args -> pure (args.greeting <> ", " <> args.name <> "!"))
      ]
  ]
```

`Arguments` is an `Applicative`, so `ado` builds a typed record without stringly
typed argument lookups in your handler. The handler receives a connected client
and the decoded argument value. Its return type determines the registered Dagger
return type. Use `pure unit` for a function with no arguments.

Supported values include `String`, `Int`, `Number`, `Boolean`, `Unit`, arrays,
`Maybe`, generated enums/scalars, and core Dagger objects such as `Container`,
`Directory`, and `File`. `Maybe` arguments may be omitted. A `defaultArgument`
registers the default with Dagger and uses it during dispatch when absent.
Object inputs are reconstructed from IDs; object results are returned as IDs.

The main object's name must match the PascalCase module name, such as
`hello-purescript` → `HelloPurescript`. Registration is explicit and checked by the
PureScript compiler: no decorators, source-text scanning, or unsafe casts.

### Constructors and stateful methods

Use a JSON-encodable PureScript record for object state:

```purescript
Module.object_ "Counter" { count: 0 }
  [ Module.constructor (Module.defaultArgument "start" 0)
      (\_ start -> pure { count: start })
  , Module.method "value" "Read the counter." (pure unit)
      (\_ state _ -> pure state.count)
  , Module.stateful "increment" "Return the incremented counter." (pure unit)
      (\_ state _ -> pure (state { count = state.count + 1 }))
  ]
```

State is decoded from the parent object supplied by Dagger on each invocation.
`stateful` returns new state as the same Dagger object type, allowing CLI chains
such as `dagger call increment value`. If you omit a constructor, the initial
state passed to `object_` becomes a no-argument constructor.

Register multiple object definitions in the array passed to `runModule` when
needed. Advanced custom values can implement `DaggerValue`; their named object
definitions must also be registered. Core enum references are supported; declaring
new module enums and interfaces is not yet provided by the authoring API.

### Module development

Run `dagger develop` after changing dependencies or API definitions. Generated
bindings are vendored under `dagger-sdk/`, and Spago discovers this package as part
of the workspace. The bootstrap preserves an existing `spago.yaml` and
`src/Main.purs`; for an existing project, add `dagger-sdk` to your package's
`dependencies` yourself.

The supplied engine schema includes installed module dependencies, so codegen can
produce their client bindings as well. Avoid naming dependency types after
handwritten SDK modules such as `Modules`, `Connection`, or `Errors`; codegen
reports a collision rather than overwriting those modules.

To run the actual module end-to-end test:

```sh
npm run test:modules
```

It creates a temporary module using this custom SDK, invokes its greeting, then
calls through a returned container to `stdout`. It cleans up its temporary source
directory afterward. This test needs Docker and network access to install the
compiler and package dependencies in the runtime image.

## Work on the SDK

| Command | What it does |
| --- | --- |
| `npm run build` | Compile all SDK modules and examples in the test tree |
| `npm test` | Run transport/scaffold tests, PureScript tests, and generated-file checks |
| `npm run generate` | Regenerate from the checked-in introspection snapshot |
| `npm run check-generated` | Check generated files without modifying them |
| `dagger run -- npm run test:integration` | Exercise client operations against an engine |
| `npm run test:modules` | Build and call a PureScript module through Dagger |

To generate against another schema:

```sh
node scripts/generate.mjs /path/to/introspection.json
```

The generator accepts a schema object, `{ "__schema": ... }`, or a standard
`{ "data": { "__schema": ... } }` response. Custom input replaces the generated
bindings in this checkout; run `npm run generate` to restore the bundled snapshot.
Do not edit generated modules directly. Full schema provenance and licensing are
in [`schema/README.md`](schema/README.md).

### Project map

```text
src/Dagger.purs             Client entry point
src/Dagger/*.purs           Generated API modules, types, and public helpers
src/Dagger/Internal/        Lazy selections and Node HTTP transport
src/Dagger/Module/          Typed definitions, value codecs, invocation protocol
scripts/                   Codegen, scaffolding, and live module smoke test
runtime/                   Custom SDK adapter and module template
schema/                    Upstream introspection snapshot and provenance
test/                      Transport, client, module, and integration tests
```

## Status and limits

This is an initial implementation, not an official Dagger SDK release.

- Client and module protocol tests pass with mocked HTTP, and a freshly scaffolded
  module compiles with zero warnings. Live Docker-backed integration remains
  unverified in this environment.
- The custom SDK manifest requests engine version `v0.21.9`. The bundled client
  bindings come from a development fixture in `../dagger`; use a matching schema
  when targeting a different engine. Module builds regenerate from the schema
  supplied by the engine.
- Sessions must already exist (`dagger run`, module invocation, or explicit
  credentials). The SDK does not download a CLI or provision an engine.
- Module state is available to methods; automatic exposed object fields, custom
  enum/interface declarations, source maps, decorators, and telemetry are not yet
  implemented.
- The generator currently requires object lists to be non-null lists with
  non-null elements, matching the bundled schema. Unsupported object-list shapes
  fail generation explicitly.
- Query execution is not memoized. Resolving object arguments or materializing
  object lists may require additional requests.

## License

Original SDK code is [MIT licensed](LICENSE). The upstream Dagger schema and API
descriptions retain their Apache-2.0 license; see [NOTICE](NOTICE),
[schema/LICENSE](schema/LICENSE), and [schema/NOTICE](schema/NOTICE).
