# Clojure examples

Runnable examples for this **personal, unofficial experimental SDK**, targeting
**Dagger 1.0.0-beta.21**.

| Example | What it demonstrates |
| --- | --- |
| [Container pipeline](pipeline/) | Connect to Dagger, execute a container, and read its output |
| [Dagger module](module/src/dagger_main.clj) | Expose a greeting and a function returning a Dagger container |

## Run the pipeline

From the repository root, install the pinned CLI first:

```sh
mise trust
mise install
```

The SDK’s `mise.toml` pins JDK 21 and Clojure. `with-open` starts and closes an owned Dagger session. Docker or another configured Dagger engine must be available.

Starting from the repository root:

```sh
cd clojure
mise trust
mise install
cd examples/pipeline
mise exec -- clojure -M:run
```

Expected output: `Hello from Clojure!` (Dagger may also print progress).

## Run the module

The module example contains the source you own. Let the SDK scaffold the package
and generate its engine-specific dependency in a separate workspace. This keeps
generated files out of the example source directory.

From the repository root:

```sh
export SDK_REPO="$PWD"
export DAGGER="$(mise which dagger)"
mkdir -p ../hello-clojure-workspace
cd ../hello-clojure-workspace
git init
"$DAGGER" init
"$DAGGER" module install "$SDK_REPO/clojure" --name clojure
"$DAGGER" module init clojure --name hello-clojure --path ./hello-clojure -y
cd hello-clojure
cp "$SDK_REPO/clojure/examples/module/src/dagger_main.clj" src/dagger_main.clj
"$DAGGER" generate -y
"$DAGGER" api call -m . hello --name developer
"$DAGGER" api call -m . container-echo --message "Hello from a module!" stdout
```

The greeting returns `Hello, developer!`. The second call returns a lazy
container and then requests its `stdout`, producing `Hello from a module!`.
Keep the generated SDK and module configuration with your module project.

See the [SDK guide](../README.md) for API details and tests.
