(ns pipeline
  (:require [dagger.core :as dag]
            [dagger.container :as container]))

(defn -main [& _]
  (with-open [client (dag/connect)]
    (print (-> (dag/container client)
               (container/from "alpine:3.22")
               (container/with-exec ["echo" "Hello from Clojure!"])
               container/stdout))))
