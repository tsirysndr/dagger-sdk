# Schema snapshot

`introspection.json` is the full introspection fixture from
`../dagger/cmd/codegen/introspection/testdata/schema.json`, at checkout commit
`366d6dd0f9ca9b6ebb9196049eb19c01e31dacf4`. It is a development snapshot,
not a promise of compatibility with every released engine.

The default generation excludes the fixture's `Test`, `Sub1`, and `Sub2`
module types. It produces 696 core fields in 61 modules. Custom schema inputs
retain user types and are used by the module SDK for dependency bindings.

Run `npm run generate` to regenerate the checked-in bindings and
`npm run check-generated` to detect drift. An explicit introspection file can
be passed to `node scripts/generate.mjs /path/to/schema.json`.

The upstream schema and its API descriptions are Apache-2.0 licensed; see
[LICENSE](LICENSE) and [../NOTICE](../NOTICE).
