import dagger
import dagger/client
import dagger/container
import gleam/io

pub fn main() {
  let assert Ok(output) =
    dagger.with_connection(fn(client) {
      client
      |> client.container
      |> container.from("alpine:3.22")
      |> container.with_exec(["echo", "Hello from Gleam!"])
      |> container.stdout
    })
  io.print(output)
}
