# Personal Dagger SDK experiments

My experimental [Dagger](https://dagger.io) SDKs for **Gleam** and **PureScript**.

**These are personal projects, not official Dagger SDKs. They are not maintained
or endorsed by the Dagger team.** I'm exploring what an idiomatic, typed Dagger
experience can look like in each language. APIs, generated bindings, and module
support may change as the experiments evolve.

Both SDKs let you build container pipelines and write Dagger modules in their
respective languages.

## Choose an SDK

| SDK | Runtime | API style | Documentation |
| --- | --- | --- | --- |
| [Gleam](gleam/) | Erlang/OTP | Pipe-friendly builders, typed options, and `Result` | [Getting started](gleam/README.md) · [Writing modules](gleam/docs/modules.md) |
| [PureScript](purescript/) | Node.js | Immutable builders, option records, and `Aff` | [Getting started](purescript/README.md) · [Writing modules](purescript/README.md#write-a-dagger-module) |

Neither SDK is published to its language's package registry yet. The individual
guides explain how to use a local checkout as a dependency.

## What can I do with them?

- Build pipelines using containers, directories, files, caches, and other Dagger objects.
- Compose lazy operations and execute them when you request a result.
- Define Dagger modules with typed arguments, return values, constructors, and state.
- Generate client bindings from a Dagger introspection schema.
- Test application code with an injected transport before connecting to an engine.

Each SDK follows its language's conventions. They share the same goals, but their
APIs and supported features are not identical; check the language-specific guide
for details and limitations.

## Get started locally

Each SDK is a separate project. Run its commands from its own directory.

### Gleam

Install Gleam 1.14+, Erlang/OTP 27+, and Python 3.12+.

```sh
cd gleam
gleam deps download
gleam test
```

Continue with the [Gleam pipeline quick start](gleam/README.md#use-the-sdk-in-an-application)
or the [Dagger module quick start](gleam/README.md#write-a-dagger-module).

### PureScript

Install Node.js 22+. The project pins PureScript and Spago as development dependencies.

```sh
cd purescript
npm install
npm run build
npm test
```

Continue with the [PureScript pipeline quick start](purescript/README.md#use-the-client-in-your-project)
or the [Dagger module quick start](purescript/README.md#write-a-dagger-module).

### Connect to a real engine

Real pipelines and module calls require the Dagger CLI and a working container
engine. From the appropriate SDK directory, run its client smoke test:

```sh
# From gleam/
dagger run -- gleam run -m live_smoke

# From purescript/
dagger run -- npm run test:integration
```

`dagger run` supplies the session credentials the clients use to connect. The
language guides also show how to initialize a Dagger module using either SDK.

## Experimental status

Local tests cover client behavior and module protocols, but mocked tests are not
a substitute for engine integration. See each SDK's README for its validation
status, engine requirements, and remaining limitations.

The bundled bindings come from an upstream development schema snapshot. They do
not guarantee compatibility with every Dagger release. Module builds regenerate
bindings from the engine-provided schema; standalone clients can regenerate them
explicitly using the instructions in their guide.

## Work on the SDKs

Start with the relevant project's development guide:

- [Gleam: development, tests, and code generation](gleam/README.md#develop-and-test)
- [PureScript: development, tests, and code generation](purescript/README.md#work-on-the-sdk)

Change generators rather than editing generated bindings directly. For bug
reports, include the SDK, compiler/runtime and Dagger versions, and a small
reproduction. Ideas for making either API feel more natural in its language are
welcome.

## License

Original SDK code is [MIT licensed](LICENSE). Upstream Dagger schemas and
schema-derived documentation retain their Apache-2.0 licensing. See the
[Gleam notice](gleam/NOTICE) and [PureScript notice](purescript/NOTICE) for attribution.
