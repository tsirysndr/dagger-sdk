# Schema snapshot

`introspection.json` was fetched from Dagger **v1.0.0-beta.21** (CLI commit
`a7a2e64e`) using `introspection.graphql`:

```sh
mise exec -- dagger query -M --doc schema/introspection.graphql > schema/introspection.json
mise exec -- clojure -M:generate
```

Run these commands from `clojure/`. The query comes from upstream Dagger’s
`cmd/codegen/introspection/introspection.graphql`. Upstream schema documentation
is Apache-2.0 licensed; see [LICENSE](LICENSE) and [NOTICE](../NOTICE).

For runnable usage, see the [examples](../examples/README.md). The
[CI workflow](../../.github/workflows/test.yml) checks that generated bindings
match this snapshot.
