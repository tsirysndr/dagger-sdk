module Test.Integration where

import Prelude
import Dagger (withConnection)
import Dagger.Container as Container
import Dagger.Directory as Directory
import Dagger.File as File
import Dagger.Query as Query
import Effect (Effect)
import Effect.Aff (launchAff_, throwError)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error)

main :: Effect Unit
main = launchAff_ $ withConnection \client -> do
  output <- Query.container client
    # Container.from "alpine:3.21"
    # Container.withExec [ "echo", "hello from PureScript" ]
    # Container.stdout
  unless (output == "hello from PureScript\n") $ throwError (error "Unexpected container output")
  let directory = Query.directory client # Directory.withNewFile "hello.txt" "PureScript"
  contents <- directory # Directory.file "hello.txt" # File.contents
  unless (contents == "PureScript") $ throwError (error "Unexpected file contents")
  mounted <- Query.container client
    # Container.from "alpine:3.21"
    # Container.withMountedDirectory "/src" directory
    # Container.withExec [ "cat", "/src/hello.txt" ]
    # Container.stdout
  unless (mounted == "PureScript") $ throwError (error "Unexpected mounted directory contents")
  liftEffect $ log "Dagger engine integration passed"
