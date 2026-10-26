import dagger
import dagger/client
import dagger/connection
import dagger/container
import dagger/internal/query
import dagger/mod
import dagger/mod/argument
import dagger/mod/codec
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn client() -> dagger.Client {
  dagger.from_connection(
    connection.with_transport(fn(_) { panic as "Unexpected request" }),
  )
}

fn greeting() -> mod.Object {
  mod.object("Greeter")
  |> mod.with_function(
    mod.function(
      "greet",
      argument.required("name", codec.string()),
      codec.string(),
      fn(_, name) { Ok("Hello " <> name) },
    ),
  )
}

pub fn typed_arguments_and_dispatch_test() {
  let assert Ok(value) =
    mod.invoke(
      [greeting()],
      "Greeter",
      "greet",
      mod.Context(client(), dynamic.nil()),
      dict.from_list([#("name", dynamic.string("Gleam"))]),
    )
  json.to_string(value) |> should.equal("\"Hello Gleam\"")
}

pub fn missing_argument_test() {
  mod.invoke(
    [greeting()],
    "Greeter",
    "greet",
    mod.Context(client(), dynamic.nil()),
    dict.new(),
  )
  |> should.equal(Error(codec.MissingArgument("name")))
}

pub fn unknown_function_test() {
  mod.invoke(
    [greeting()],
    "Greeter",
    "absent",
    mod.Context(client(), dynamic.nil()),
    dict.new(),
  )
  |> should.equal(Error(codec.UnknownFunction("Greeter", "absent")))
}

pub fn paired_arguments_test() {
  let arguments =
    argument.pair(
      argument.required("text", codec.string()),
      argument.optional("times", codec.int()),
    )
  argument.decode(
    arguments,
    client(),
    dict.from_list([#("text", dynamic.string("hi"))]),
  )
  |> should.equal(Ok(#("hi", None)))
  argument.decode(
    arguments,
    client(),
    dict.from_list([#("text", dynamic.string("hi")), #("times", dynamic.int(3))]),
  )
  |> should.equal(Ok(#("hi", Some(3))))
}

pub fn nullable_list_codec_test() {
  let value = codec.list(codec.optional(codec.int()))
  let assert Ok(encoded) = codec.encode(value, [Some(1), None, Some(3)])
  let assert Ok(data) = json.parse(json.to_string(encoded), decode.dynamic)
  codec.decode(value, client(), data)
  |> should.equal(Ok([Some(1), None, Some(3)]))
  let assert Error(codec.InvalidValue(_)) =
    codec.decode(value, client(), dynamic.string("wrong"))
}

pub fn object_input_codec_is_lazy_test() {
  let assert Ok(value) =
    codec.decode(container.codec(), client(), dynamic.string("container-id"))
  query.select(value.selection, "stdout", [])
  |> query.render
  |> should.equal(Ok(
    "query{node(id:\"container-id\"){... on Container{stdout}}}",
  ))
}

pub fn engine_object_return_serializes_id_test() {
  let dag =
    dagger.from_connection(
      connection.with_transport(fn(body) {
        json.parse(body, decode.at(["query"], decode.string))
        |> should.equal(Ok("query{container{id}}"))
        Ok(#(200, "{\"data\":{\"container\":{\"id\":\"container-id\"}}}"))
      }),
    )
  let assert Ok(value) = codec.encode(container.codec(), client.container(dag))
  json.to_string(value) |> should.equal("\"container-id\"")
}

pub fn constructor_and_state_test() {
  let state_codec =
    codec.object("Counter", decode.at(["count"], decode.int), fn(count) {
      json.object([#("count", json.int(count))])
    })
  let object =
    mod.object("Counter")
    |> mod.with_field("count", codec.int())
    |> mod.with_constructor(
      argument.required("start", codec.int()),
      state_codec,
      fn(_, start) { Ok(start) },
    )
    |> mod.with_function(
      mod.function("next", argument.none(), state_codec, fn(ctx, _) {
        let assert Ok(count) = mod.parent(ctx, state_codec)
        Ok(count + 1)
      }),
    )
  let assert Ok(initial) =
    mod.invoke(
      [object],
      "Counter",
      "",
      mod.Context(client(), dynamic.nil()),
      dict.from_list([#("start", dynamic.int(4))]),
    )
  let assert Ok(parent) = json.parse(json.to_string(initial), decode.dynamic)
  let assert Ok(next) =
    mod.invoke(
      [object],
      "Counter",
      "next",
      mod.Context(client(), parent),
      dict.new(),
    )
  json.to_string(next) |> should.equal("{\"count\":5}")
}

pub fn duplicate_definitions_test() {
  let assert Error(codec.InvalidDefinition(_)) =
    mod.validate([greeting(), greeting()])
}

pub fn default_constructor_test() {
  let assert Ok(value) =
    mod.invoke(
      [greeting()],
      "Greeter",
      "",
      mod.Context(client(), dynamic.nil()),
      dict.new(),
    )
  json.to_string(value) |> should.equal("{}")
}

pub fn invocation_protocol_test() {
  let dag =
    dagger.from_connection(
      connection.with_transport(fn(body) {
        let assert Ok(document) =
          json.parse(body, decode.at(["query"], decode.string))
        case document {
          "query{currentFunctionCall{parentName name parent inputArgs{name value}}}" ->
            Ok(#(
              200,
              "{\"data\":{\"currentFunctionCall\":{\"parentName\":\"Greeter\",\"name\":\"greet\",\"parent\":\"{}\",\"inputArgs\":[{\"name\":\"name\",\"value\":\"\\\"Gleam\\\"\"}]}}}",
            ))
          "query{currentFunctionCall{returnValue(value:\"\\\"Hello Gleam\\\"\")}}" ->
            Ok(#(
              200,
              "{\"data\":{\"currentFunctionCall\":{\"returnValue\":null}}}",
            ))
          _ -> panic as document
        }
      }),
    )
  mod.serve_with_client(dag, greeting(), []) |> should.equal(Ok(Nil))
}

@external(erlang, "registration_test_ffi", "respond")
fn registration_response(document: String) -> String

@external(erlang, "registration_test_ffi", "seen")
fn registration_queries() -> List(String)

@external(erlang, "registration_test_ffi", "reset")
fn reset_registration_queries() -> Nil

pub fn module_registration_protocol_test() {
  reset_registration_queries()
  let dag =
    dagger.from_connection(
      connection.with_transport(fn(body) {
        let assert Ok(document) =
          json.parse(body, decode.at(["query"], decode.string))
        Ok(#(200, registration_response(document)))
      }),
    )
  let object =
    greeting()
    |> mod.with_field("enabled", codec.bool())
    |> mod.with_function(
      mod.function(
        "values",
        argument.none(),
        codec.list(codec.optional(codec.int())),
        fn(_, _) { Ok([None]) },
      ),
    )
  let assert Ok(id) = mod.register(dag, [object])
  json.to_string(id) |> should.equal("\"registered-id\"")
  let queries = registration_queries()
  queries
  |> list.any(fn(q) { string.contains(q, "withObject(name:\"Greeter\"") })
  |> should.be_true
  queries
  |> list.any(fn(q) { string.contains(q, "withArg(name:\"name\"") })
  |> should.be_true
  queries
  |> list.any(fn(q) { string.contains(q, "withOptional(optional:true)") })
  |> should.be_true
  queries
  |> list.any(fn(q) {
    string.contains(q, "withListOf(elementType:\"registered-id\")")
  })
  |> should.be_true
  queries
  |> list.any(fn(q) { string.contains(q, "withField(name:\"enabled\"") })
  |> should.be_true
}

pub fn exposed_state_field_test() {
  let object = mod.object("Counter") |> mod.with_field("count", codec.int())
  let state = dynamic.properties([#(dynamic.string("count"), dynamic.int(7))])
  let assert Ok(value) =
    mod.invoke(
      [object],
      "Counter",
      "count",
      mod.Context(client(), state),
      dict.new(),
    )
  json.to_string(value) |> should.equal("7")
}

pub fn constructor_accepts_empty_parent_json_test() {
  let dag =
    dagger.from_connection(
      connection.with_transport(fn(body) {
        let assert Ok(document) =
          json.parse(body, decode.at(["query"], decode.string))
        case document {
          "query{currentFunctionCall{parentName name parent inputArgs{name value}}}" ->
            Ok(#(
              200,
              "{\"data\":{\"currentFunctionCall\":{\"parentName\":\"Greeter\",\"name\":\"\",\"parent\":\"\",\"inputArgs\":[]}}}",
            ))
          "query{currentFunctionCall{returnValue(value:\"{}\")}}" ->
            Ok(#(
              200,
              "{\"data\":{\"currentFunctionCall\":{\"returnValue\":null}}}",
            ))
          _ -> panic as document
        }
      }),
    )
  mod.serve_with_client(dag, greeting(), []) |> should.equal(Ok(Nil))
}
