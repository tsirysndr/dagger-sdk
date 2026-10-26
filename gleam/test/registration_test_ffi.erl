-module(registration_test_ffi).
-export([respond/1, seen/0, reset/0]).
reset() -> put(dagger_registration_queries, []), nil.
seen() -> case get(dagger_registration_queries) of undefined -> []; Queries -> lists:reverse(Queries) end.
respond(Document) ->
    put(dagger_registration_queries, [Document | lists:reverse(seen())]),
    Bare = re:replace(Document, <<"\\([^)]*\\)">>, <<>>, [global, {return, binary}]),
    [<<"query">> | Fields] = re:split(Bare, <<"[{} ]+">>, [{return, binary}, trim]),
    Data = lists:foldr(fun(Field, Acc) -> #{Field => Acc} end, <<"registered-id">>, Fields),
    iolist_to_binary(json:encode(#{<<"data">> => Data})).
