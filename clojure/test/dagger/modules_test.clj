(ns dagger.modules-test
  (:require [clojure.test :refer [deftest is]]
            [clojure.data.json :as json]
            [dagger.core :as dag]
            [dagger.client-test :refer [mocked error-type]]
            [dagger.modules :as modules]))

(defn ^{:dagger/return :string} hello
  "A normal Clojure function, also exported through Dagger."
  [^{:tag String :dagger/default "world"} who]
  (str "Hello " who))

(defn ^{:dagger/return :string} with-context
  [^:dagger/context context ^String text]
  (assert (:client context))
  text)

(defn helper [x] (str x))

(deftest idiomatic-defn-exports
  (let [module (modules/from-ns 'dagger.modules-test "Greeting") client (mocked (constantly {}))]
    (is (= #{:hello :with-context} (set (keys (:functions module)))))
    (is (= "Hello world" (modules/invoke! module client "Greeting" "hello" {} {})))
    (is (= "Hello Clojure" (modules/invoke! module client "Greeting" "hello" {} {"who" "Clojure"})))
    (is (= "ok" (modules/invoke! module client "Greeting" "with_context" {} {"text" "ok"})))
    (is (= :dagger/module (error-type #(modules/invoke! module client "Greeting" "hello" {} {"who" 12}))))))

(def counter
  {:name "Counter" :fields {:count :int}
   :constructor {:args {:start {:type :int :default 0}} :fn (fn [_ {:keys [start]}] {:count start})}
   :functions {:increment {:args {} :returns [:object "Counter"] :fn (fn [{:keys [parent]} _] (update parent :count inc))}}})

(deftest constructors-and-state
  (let [client (mocked (constantly {}))]
    (is (= {"count" 4} (modules/invoke! counter client "Counter" "" nil {"start" 4})))
    (is (= {"count" 5} (modules/invoke! counter client "Counter" "increment" {"count" 4} {})))
    (is (= 7 (modules/invoke! counter client "Counter" "count" {"count" 7} {})))
    (is (= :dagger/module (error-type #(modules/invoke! counter client "Counter" "missing" {"count" 1} {}))))))

(deftest nested-types
  (let [m {:name "Values" :enums {"Mood" ["HAPPY" "SAD"]}} client (mocked (constantly {}))]
    (is (= ["HAPPY" nil] (modules/encode-value m [:list [:optional [:enum "Mood"]]] [:happy nil])))
    (is (= [:happy nil] (modules/decode-value m client [:list [:optional [:enum "Mood"]]] ["HAPPY" nil])))
    (is (= :dagger/module (error-type #(modules/encode-value m :int "wrong"))))))

(deftest invocation-protocol
  (let [requests (atom [])
        client (mocked (fn [request]
                         (swap! requests conj request)
                         (if (= "query{currentFunctionCall{parentName name parent inputArgs{name value}}}" (:query request))
                           {"currentFunctionCall" {"parentName" "Greeting" "name" "hello" "parent" "{}"
                                                   "inputArgs" [{"name" "who" "value" "\"Clojure\""}]}}
                           {"currentFunctionCall" {"returnValue" nil}})))
        module (modules/from-ns 'dagger.modules-test "Greeting")]
    (is (nil? (modules/serve-with-client! client module)))
    (is (= "\"Hello Clojure\"" (get-in @requests [1 :variables "v0"]))))

)
