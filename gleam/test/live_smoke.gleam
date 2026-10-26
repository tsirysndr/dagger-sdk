//// Run explicitly with: dagger api with-session -- gleam run -m live_smoke

import dagger
import dagger/client
import dagger/container
import gleam/io
import gleam/result

pub fn main() {
  let assert Ok(output) =
    dagger.with_connection(fn(dag) {
      use container <- result.try(
        dag
        |> client.container
        |> container.from("alpine:3.22")
        |> container.with_exec(["echo", "hello from Gleam"])
        |> container.sync,
      )
      container.stdout(container)
    })
  io.println(output)
}
