(ns dagger.integration
  (:require [dagger.core :as dag]
            [dagger.container :as container]
            [dagger.directory :as directory]
            [dagger.env-variable :as env]
            [dagger.file :as file]))

(defn -main [& _]
  (with-open [client (dag/connect)]
    (let [source (-> (dag/directory client) (directory/with-new-file "hello.txt" "Hello from Clojure!"))
          image (-> (dag/container client) (container/from "alpine:3.22")
                    (container/with-directory "/src" source)
                    (container/with-exec ["cat" "/src/hello.txt"]))]
      (assert (= "Hello from Clojure!" (container/stdout image)))
      (assert (= "Hello from Clojure!" (-> source (directory/file "hello.txt") file/contents)))
      (assert (= "Hello from Clojure!" (-> image container/sync container/stdout)))
      (let [variables (-> image (container/with-env-variable "SDK_TEST" "clojure") container/env-variables)]
        (assert (some #(and (= "SDK_TEST" (env/name %)) (= "clojure" (env/value %))) variables)))
      (println "Live Dagger client checks passed."))))
