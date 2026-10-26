(ns dagger.codegen-test
  (:require [clojure.test :refer [deftest is]]
            [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.edn :as edn]
            [dagger.codegen :as codegen]
            [dagger.scaffold :as scaffold]))

(deftest generated-bindings-match-and-load
  (is (nil? (codegen/generate! "schema/introspection.json" "." true)))
  (doseq [path (keys (codegen/outputs (json/read-str (slurp "schema/introspection.json") :key-fn keyword)))
          :when (.endsWith path ".clj")]
    (let [form (with-open [reader (java.io.PushbackReader. (io/reader path))] (read reader))]
      (require (second form))
      (is (find-ns (second form))))))

(deftest scaffold-preserves-source-and-settings
  (let [dir (.toFile (java.nio.file.Files/createTempDirectory "clojure-sdk-scaffold" (make-array java.nio.file.attribute.FileAttribute 0)))
        source (io/file dir "src/dagger_main.clj") config (io/file dir "deps.edn")]
    (try
      (spit config "{:paths [\"custom\"] :aliases {:dev {:extra-paths [\"dev\"]}}}")
      (scaffold/initialize! dir "hello-clojure" "runtime/template/src/dagger_main.clj")
      (is (= ["src" "custom"] (:paths (edn/read-string (slurp config)))))
      (is (= {:dev {:extra-paths ["dev"]}} (:aliases (edn/read-string (slurp config)))))
      (spit source ";; my code")
      (scaffold/initialize! dir "hello-clojure" "runtime/template/src/dagger_main.clj")
      (is (= ";; my code" (slurp source)))
      (finally (doseq [f (reverse (file-seq dir))] (io/delete-file f))))))
