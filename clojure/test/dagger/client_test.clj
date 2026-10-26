(ns dagger.client-test
  (:require [clojure.test :refer [deftest is testing]]
            [clojure.data.json :as json]
            [clojure.string :as str]
            [dagger.core :as dag]
            [dagger.client :as client]
            [dagger.connection :as connection]
            [dagger.container :as container]
            [dagger.directory :as directory]
            [dagger.env-variable :as env]
            [dagger.internal.runtime :as runtime])
  (:import [com.sun.net.httpserver HttpServer HttpHandler]
           [java.net InetSocketAddress]
           [java.nio.charset StandardCharsets]
           [java.util Base64]))

(defn mocked [handler] (connection/with-transport #(hash-map :status 200 :body (json/write-str {:data (handler %)}))))
(defn error-type [f] (try (f) nil (catch clojure.lang.ExceptionInfo e (:type (ex-data e)))))

(deftest lazy-pipeline-and-variables
  (let [calls (atom []) client (mocked (fn [request] (swap! calls conj request) {"container" {"from" {"withExec" {"stdout" "hello"}}}}))
        object (-> (dag/container client) (container/from "alpine") (container/with-exec ["echo" "hello"]))]
    (is (empty? @calls))
    (is (= "hello" (container/stdout object)))
    (is (= {"v0" "alpine" "v1" ["echo" "hello"]} (:variables (first @calls))))
    (is (= "query($v0:String!,$v1:[String!]!){container{from(address:$v0){withExec(args:$v1){stdout}}}}" (:query (first @calls))))))

(deftest arguments-are-json-not-interpolation
  (let [text "quote\" slash\\ newline\n 🦋 {evil}" client (mocked (constantly {}))
        document (-> (dag/container client) (container/from text) runtime/document)]
    (is (not (str/includes? (:query document) text)))
    (is (= text (get-in document [:variables "v0"])))
    (is (= text (get-in (json/read-str (json/write-str document)) ["variables" "v0"])))))

(deftest options-inputs-and-errors
  (let [client (mocked (constantly {})) object (dag/container client)]
    (is (= :dagger/invalid-argument (error-type #(container/with-exec object [] {:typo true}))))
    (is (= :dagger/invalid-argument (error-type #(container/from (dag/directory client) "alpine"))))
    (is (= :dagger/invalid-argument (error-type #(runtime/document (container/from object nil)))))
    (is (= :dagger/invalid-argument (error-type #(runtime/document (container/with-exec object [1])))))
    (is (= false (get-in (runtime/document (container/with-exec object [] {:use-entrypoint false})) [:variables "v1"])))
    (is (= "ANY" (get-in (runtime/document (container/with-exec object [] {:expect :any})) [:variables "v1"])))
    (is (= :dagger/invalid-argument (error-type #(runtime/document (container/with-exec object [] {:expect :unknown})))))))

(deftest lazy-object-arguments
  (let [calls (atom []) client (mocked (fn [request]
                                        (swap! calls conj request)
                                        (if (= "query{directory{id}}" (:query request))
                                          {"directory" {"id" "directory-id"}}
                                          {"container" {"withDirectory" {"stdout" "ok"}}})))
        source (dag/directory client)
        object (container/with-directory (dag/container client) "/src" source)]
    (is (empty? @calls))
    (is (= "ok" (container/stdout object)))
    (is (= 2 (count @calls)))
    (is (= "directory-id" (get-in @calls [1 :variables "v1"])))
    (is (= :dagger/invalid-argument
           (error-type #(-> (dag/container (mocked (constantly {}))) (container/with-directory "/src" source) runtime/document))))))

(deftest object-lists-reload-and-sync
  (let [client (mocked #(case (:query %)
                         "query{container{envVariables{id}}}" {"container" {"envVariables" [{"id" "env-id"}]}}
                         "query($v0:ID!){node(id:$v0){... on EnvVariable{name}}}" {"node" {"name" "HOME"}}
                         "query{container{sync}}" {"container" {"sync" "container-id"}}))]
    (is (= "HOME" (-> (dag/container client) container/env-variables first env/name)))
    (is (= "Container" (:type-name (container/sync (dag/container client)))))))

(deftest error-data-and-close
  (let [closed (atom 0) client (connection/with-transport
                               (constantly {:status 200 :body "{\"data\":null,\"errors\":[{\"message\":\"exec failed\",\"path\":[\"container\"],\"extensions\":{\"exitCode\":2}}]}"})
                               #(swap! closed inc))]
    (try (dag/query! client "query{id}") (is false)
         (catch clojure.lang.ExceptionInfo e
           (is (= :dagger/graphql (:type (ex-data e))))
           (is (= 2 (get-in (ex-data e) [:errors 0 "extensions" "exitCode"])))))
    (.close client) (.close client)
    (is (= 1 @closed))
    (is (= :dagger/closed (error-type #(dag/query! client "query{id}")))))
  (doseq [[response expected] [[{:status 403 :body "denied"} :dagger/http]
                                [{:status 200 :body "{"} :dagger/decode]
                                [{:status 200 :body "{}"} :dagger/decode]
                                [{:status 200 :body "{\"errors\":42,\"data\":{}}"} :dagger/decode]]]
    (is (= expected (error-type #(dag/query! (connection/with-transport (constantly response)) "query{id}"))))))

(deftest actual-http-transport
  (let [received (promise)
        server (HttpServer/create (InetSocketAddress. "127.0.0.1" 0) 0)]
    (.createContext server "/query"
                    (reify HttpHandler
                      (handle [_ exchange]
                        (deliver received {:method (.getRequestMethod exchange)
                                           :auth (.getFirst (.getRequestHeaders exchange) "Authorization")
                                           :upgrade (.getFirst (.getRequestHeaders exchange) "Upgrade")
                                           :body (slurp (.getRequestBody exchange))})
                        (let [body (.getBytes "{\"data\":{\"version\":\"test\"}}" StandardCharsets/UTF_8)]
                          (.sendResponseHeaders exchange 200 (count body))
                          (with-open [stream (.getResponseBody exchange)] (.write stream body))))))
    (.start server)
    (try
      (with-open [client (connection/connect {:port (.getPort (.getAddress server)) :token "test-token"})]
        (is (= {"version" "test"} (dag/query! client "query{version}")))
        (is (= "POST" (:method @received)))
        (is (nil? (:upgrade @received)))
        (is (= (str "Basic " (.encodeToString (Base64/getEncoder) (.getBytes "test-token:" StandardCharsets/UTF_8))) (:auth @received))))
      (finally (.stop server 0)))))
