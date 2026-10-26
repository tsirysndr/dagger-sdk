module Examples.Pipeline where

import Prelude
import Dagger (withConnection)
import Dagger.Container as Container
import Dagger.Query as Query
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)

main :: Effect Unit
main = launchAff_ $ withConnection \client -> do
  output <- Query.container client
    # Container.from "alpine:3.22"
    # Container.withExec [ "echo", "Hello from PureScript!" ]
    # Container.stdout
  liftEffect $ log output
