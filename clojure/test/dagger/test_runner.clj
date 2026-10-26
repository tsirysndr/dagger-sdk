(ns dagger.test-runner
  (:require [clojure.test :as test]
            [dagger.client-test]
            [dagger.modules-test]
            [dagger.codegen-test]))

(defn -main [& _]
  (let [result (test/run-tests 'dagger.client-test 'dagger.modules-test 'dagger.codegen-test)]
    (shutdown-agents)
    (when (pos? (+ (:fail result) (:error result))) (System/exit 1))))
