# PureScript examples

Runnable examples for this **personal, unofficial experimental SDK**, targeting
**Dagger 1.0.0-beta.21**.

| Example | What it demonstrates |
| --- | --- |
| [Container pipeline](pipeline/) | Connect to Dagger, execute a container, and read its output |
| [Dagger module](module/src/Main.purs) | Expose a greeting and a function returning a Dagger container |

## Run the pipeline

From the repository root, install the pinned CLI first:

```sh
mise trust
mise install
```

Install Node.js 22 or newer. The pipeline builds in the SDK workspace, using its pinned Spago and PureScript versions. Docker or another configured Dagger engine must be available.

Starting from the repository root:

```sh
cd purescript
npm install
npx spago build --purs-args "examples/pipeline/src/**/*.purs"
mise exec -- dagger api with-session -- node examples/pipeline/run.mjs
```

Expected output: `Hello from PureScript!` (Dagger may also print progress).

## Run the module

The module example contains the source you own. Let the SDK scaffold the package
and generate its engine-specific dependency in a separate workspace. This keeps
generated files out of the example source directory.

From the repository root:

```sh
export SDK_REPO="$PWD"
export DAGGER="$(mise which dagger)"
mkdir -p ../hello-purescript-workspace
cd ../hello-purescript-workspace
git init
"$DAGGER" init
"$DAGGER" module install "$SDK_REPO/purescript" --name purescript
"$DAGGER" module init purescript --name hello-purescript --path ./hello-purescript -y
cd hello-purescript
cp "$SDK_REPO/purescript/examples/module/src/Main.purs" src/Main.purs
"$DAGGER" generate -y
"$DAGGER" api call -m . hello --name developer
"$DAGGER" api call -m . container --message "Hello from a module!" stdout
```

The greeting returns `Hello, developer!`. The second call returns a lazy
container and then requests its `stdout`, producing `Hello from a module!`.
Keep the generated SDK and module configuration with your module project.

See the [SDK guide](../README.md) for API details and tests.
