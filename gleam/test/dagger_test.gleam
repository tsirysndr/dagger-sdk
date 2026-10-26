import dagger/cache_sharing_mode
import dagger/client
import dagger/connection
import dagger/container
import dagger/directory
import dagger/errors
import dagger/internal/query
import dagger/types
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn mock(expected: String, response: String) -> types.Query {
  let conn =
    connection.with_transport(fn(body) {
      json.parse(body, decode.at(["query"], decode.string))
      |> should.equal(Ok(expected))
      Ok(#(200, response))
    })
  types.Query(query.root(conn))
}

pub fn lazy_container_pipeline_test() {
  mock(
    "query{container{from(address:\"alpine:3.22\"){withExec(args:[\"echo\",\"hello\"]){stdout}}}}",
    "{\"data\":{\"container\":{\"from\":{\"withExec\":{\"stdout\":\"hello\\n\"}}}}}",
  )
  |> client.container
  |> container.from("alpine:3.22")
  |> container.with_exec(["echo", "hello"])
  |> container.stdout
  |> should.equal(Ok("hello\n"))
}

pub fn lazy_build_does_not_send_test() {
  let conn = connection.with_transport(fn(_) { panic as "Must stay lazy" })
  let dag = types.Query(query.root(conn))
  let _ =
    dag
    |> client.container
    |> container.from("alpine")
    |> container.with_exec(["true"])
}

pub fn options_and_enums_test() {
  let dag = mock("", "")
  dag
  |> client.container_with([
    client.ContainerPlatform(types.Platform("linux/arm64")),
  ])
  |> container.with_exec_with(["true"], [container.WithExecUseEntrypoint(True)])
  |> fn(c) { query.render(c.selection) }
  |> should.equal(Ok(
    "query{container(platform:\"linux/arm64\"){withExec(args:[\"true\"],useEntrypoint:true)}}",
  ))
  cache_sharing_mode.encode(cache_sharing_mode.Locked)
  |> query.encode
  |> should.equal(Ok("LOCKED"))
}

pub fn strings_are_graphql_safe_test() {
  let value =
    "quote\" slash\\ newline\n tab\t return\r backspace\u{0008} formfeed\u{000C} unicode 🦋"
  let assert Ok(encoded) = query.encode(query.String(value))
  json.parse(encoded, decode.string) |> should.equal(Ok(value))
}

pub fn nested_values_test() {
  query.Object([
    #("items", query.List([query.Int(2), query.Boolean(False), query.Null])),
  ])
  |> query.encode
  |> should.equal(Ok("{items:[2,false,null]}"))
  query.optional(None, query.String) |> query.encode |> should.equal(Ok("null"))
  query.optional(Some("x"), query.String)
  |> query.encode
  |> should.equal(Ok("\"x\""))
}

pub fn object_argument_is_resolved_lazily_test() {
  let source =
    mock(
      "query{directory{id}}",
      "{\"data\":{\"directory\":{\"id\":\"dir-id\"}}}",
    )
    |> client.directory
  mock(
    "query{container{withDirectory(path:\"/src\",source:\"dir-id\"){stdout}}}",
    "{\"data\":{\"container\":{\"withDirectory\":{\"stdout\":\"ok\"}}}}",
  )
  |> client.container
  |> container.with_directory("/src", source)
  |> container.stdout
  |> should.equal(Ok("ok"))
}

pub fn object_lists_reload_by_id_test() {
  let c =
    mock(
      "query{container{envVariables{id}}}",
      "{\"data\":{\"container\":{\"envVariables\":[{\"id\":\"one\"},{\"id\":\"two\"}]}}}",
    )
    |> client.container
  let assert Ok([one, two]) = container.env_variables(c)
  query.render(one.selection)
  |> should.equal(Ok("query{node(id:\"one\"){... on EnvVariable}}"))
  query.render(two.selection)
  |> should.equal(Ok("query{node(id:\"two\"){... on EnvVariable}}"))
}

pub fn graphql_errors_preserve_details_test() {
  let result =
    mock(
      "query{container{stdout}}",
      "{\"data\":{\"container\":null},\"errors\":[{\"message\":\"exec failed\",\"path\":[\"container\",\"stdout\"],\"extensions\":{\"exitCode\":42}}]}",
    )
    |> client.container
    |> container.stdout
  let assert Error(errors.GraphQLErrors([error])) = result
  error.message |> should.equal("exec failed")
  decode.run(error.extensions, decode.at(["exitCode"], decode.int))
  |> should.equal(Ok(42))
}

pub fn http_error_test() {
  let conn = connection.with_transport(fn(_) { Ok(#(401, "unauthorized")) })
  query.request(conn, "query{id}")
  |> should.equal(Error(errors.HttpError(401, "unauthorized")))
}

pub fn transport_error_test() {
  let conn =
    connection.with_transport(fn(_) { Error(errors.TransportError("offline")) })
  query.request(conn, "query{id}")
  |> should.equal(Error(errors.TransportError("offline")))
}

pub fn invalid_json_test() {
  let conn = connection.with_transport(fn(_) { Ok(#(200, "{")) })
  let assert Error(errors.InvalidJson(_)) = query.request(conn, "query{id}")
}

pub fn invalid_response_shape_test() {
  let result =
    mock(
      "query{directory{entries}}",
      "{\"data\":{\"directory\":{\"entries\":12}}}",
    )
    |> client.directory
    |> directory.entries
  let assert Error(errors.DecodeError(_)) = result
}

pub fn missing_data_test() {
  let conn = connection.with_transport(fn(_) { Ok(#(200, "{}")) })
  let assert Error(errors.DecodeError(_)) = query.request(conn, "query{id}")
}

pub fn malformed_errors_not_silenced_test() {
  let conn =
    connection.with_transport(fn(_) {
      Ok(#(200, "{\"errors\":42,\"data\":{}}"))
    })
  let assert Error(errors.DecodeError(_)) = query.request(conn, "query{id}")
}

pub fn sync_returns_a_typed_object_test() {
  let assert Ok(value) =
    mock(
      "query{container{sync}}",
      "{\"data\":{\"container\":{\"sync\":\"synced\"}}}",
    )
    |> client.container
    |> container.sync
  query.select(value.selection, "stdout", [])
  |> query.render
  |> should.equal(Ok("query{node(id:\"synced\"){... on Container{stdout}}}"))
}

pub fn repeated_options_last_wins_test() {
  mock("", "")
  |> client.container
  |> container.with_exec_with(["true"], [
    container.WithExecUseEntrypoint(False),
    container.WithExecUseEntrypoint(True),
  ])
  |> fn(c) { query.render(c.selection) }
  |> should.equal(Ok(
    "query{container{withExec(args:[\"true\"],useEntrypoint:true)}}",
  ))
}
