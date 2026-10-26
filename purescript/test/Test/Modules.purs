module Test.Modules (run) where

import Prelude
import Data.Argonaut.Core (fromString, jsonNull)
import Data.Argonaut.Encode (encodeJson)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Dagger as Dagger
import Dagger.Container as Container
import Dagger.Module.Runtime (invoke, register, serve)
import Dagger.Modules as Module
import Dagger.Query as Query
import Effect (Effect)
import Effect.Aff (Aff, bracket, throwError, try)
import Effect.Class (liftEffect)
import Effect.Exception (error)
import Foreign.Object as Object

foreign import installMock :: Effect (Effect Unit)
foreign import setCall :: String -> String -> String -> Effect Unit
foreign import verifyResult :: String -> Effect Unit
foreign import verifyRegistration :: Effect Unit

run :: Aff Unit
run = bracket (liftEffect installMock) liftEffect \_ -> do
  client <- liftEffect $ Dagger.connectWith { port: 12345, token: "module-token", timeoutMs: 1000 }
  let
    defs =
      [ Module.object_ "Counter" { count: 0 }
          [ Module.constructor (Module.defaultArgument "start" 0) (\_ start -> pure { count: start })
          , Module.method "add" "Add an integer."
              (Module.argument "amount") (\_ state amount -> pure (state.count + amount))
          , Module.stateful "increment" "Return updated state." (pure unit)
              (\_ state _ -> pure (state { count = state.count + 1 }))
          , Module.function "greet" "Compose argument records."
              (ado
                name <- Module.defaultArgument "name" "world"
                suffix <- Module.argument "suffix"
                in { name, suffix })
              (\_ args -> pure (args.name <> case args.suffix of
                Nothing -> "!"
                Just suffix -> suffix))
          , Module.function "container" "Return a core Dagger object." (pure unit)
              (\dag _ -> pure (Query.container dag # Container.from "alpine:3.21"))
          ]
      ]
    call name parent args = invoke client defs { parentName: "Counter", name, parent, args }
  initialized <- call "" jsonNull (Object.singleton "start" (encodeJson 3))
  unless (initialized == encodeJson { count: 3 }) $ throwError (error "constructor failed")
  added <- call "add" initialized (Object.singleton "amount" (encodeJson 2))
  unless (added == encodeJson 5) $ throwError (error "state or arguments failed")
  next <- call "increment" initialized Object.empty
  unless (next == encodeJson { count: 4 }) $ throwError (error "state transition failed")
  greeting <- call "greet" initialized Object.empty
  unless (greeting == fromString "world!") $ throwError (error "optional/default/applicative arguments failed")
  invalid <- try $ call "add" initialized (Object.singleton "amount" (fromString "bad"))
  case invalid of
    Left _ -> pure unit
    Right _ -> throwError (error "invalid argument accepted")
  missing <- try $ call "noSuchFunction" initialized Object.empty
  case missing of
    Left _ -> pure unit
    Right _ -> throwError (error "unknown function accepted")
  core <- call "container" initialized Object.empty
  unless (core == fromString "test-id") $ throwError (error "core object return encoding failed")
  void $ register client defs
  liftEffect verifyRegistration
  -- Drive the same registration/invocation protocol used by the engine.
  liftEffect $ setCall "Counter" "add" "{\"count\":3}"
  serve client defs
  liftEffect $ verifyResult "5"
  liftEffect $ setCall "" "" "null"
  serve client defs
  liftEffect $ verifyResult "\"test-id\""
  duplicate <- try $ register client (defs <> defs)
  case duplicate of
    Left _ -> pure unit
    Right _ -> throwError (error "duplicate object names accepted")
