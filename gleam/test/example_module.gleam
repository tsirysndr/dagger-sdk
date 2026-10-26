import dagger/client
import dagger/container
import dagger/mod
import dagger/mod/argument
import dagger/mod/codec

/// This is your module's entrypoint. Add functions to definition() below.
pub fn main() {
  let assert Ok(_) = mod.serve(definition(), [])
}

pub fn definition() -> mod.Object {
  mod.object("Example")
  |> mod.with_description("A Dagger module written in Gleam")
  |> mod.with_function(
    mod.function(
      "hello",
      argument.required("name", codec.string()),
      codec.string(),
      fn(_context, name) { Ok("Hello, " <> name <> "!") },
    ),
  )
  |> mod.with_function(
    mod.function(
      "container_echo",
      argument.required("message", codec.string()),
      container.codec(),
      fn(context, message) {
        Ok(
          context.client
          |> client.container
          |> container.from("alpine:3.22")
          |> container.with_exec(["echo", message]),
        )
      },
    ),
  )
}
