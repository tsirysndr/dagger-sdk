module Test.Main where

import Prelude
import Dagger as Dagger
import Dagger.Container as Container
import Dagger.Directory as Directory
import Dagger.EnvVariable as EnvVariable
import Dagger.Query as Query
import Dagger.Types (ReturnType(..))
import Data.Array (head)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (bracket, launchAff_, throwError)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error)
import Test.Modules as Modules

foreign import installMock :: Effect (Effect Unit)
foreign import verifyMock :: Effect Unit

main :: Effect Unit
main = launchAff_ $ bracket (liftEffect installMock) liftEffect \_ -> do
  client <- liftEffect $ Dagger.connectWith { port: 12345, token: "test-token", timeoutMs: 1000 }
  let
    base = Query.container client # Container.from "alpine:3.21"
    options = Container.defaultWithExecOpts { stdin = Just "hello\n", expect = Just ReturnTypeAny, useEntrypoint = Just false }
    command = base # Container.withExecWith [ "cat" ] options
    directory = Query.directory client # Directory.withNewFile "hello.txt" "hello"
    mounted = base # Container.withMountedDirectory "/src" directory
  output <- Container.stdout command
  unless (output == "hello\n") $ throwError (error "stdout decoding failed")
  first <- Container.stdout mounted
  second <- Container.stdout mounted
  unless (first == "mounted" && second == first) $ throwError (error "object arguments or immutability failed")
  value <- Container.envVariable "MISSING" base
  unless (value == Nothing) $ throwError (error "nullable decoding failed")
  envs <- Container.envVariables base
  case head envs of
    Nothing -> throwError (error "object list decoding failed")
    Just env -> do
      name <- EnvVariable.name env
      unless (name == "HOME") $ throwError (error "object list selection failed")
  liftEffect verifyMock
  Modules.run
  liftEffect $ log "PureScript SDK tests passed"
