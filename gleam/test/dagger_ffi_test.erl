-module(dagger_ffi_test).
-include_lib("eunit/include/eunit.hrl").

with_env(Fun) ->
    Keys = ["DAGGER_SESSION_PORT", "DAGGER_SESSION_TOKEN", "_EXPERIMENTAL_DAGGER_CLI_BIN", "DAGGER_TEST_MODE"],
    Saved = [{K, os:getenv(K)} || K <- Keys],
    lists:foreach(fun os:unsetenv/1, Keys),
    os:putenv("_EXPERIMENTAL_DAGGER_CLI_BIN", filename:absname("test/fake_dagger.py")),
    try Fun()
    after lists:foreach(fun({K, false}) -> os:unsetenv(K); ({K, V}) -> os:putenv(K, V) end, Saved)
    end.

session_and_close_test() -> with_env(fun() ->
    {ok, Session = {session, _, _, Pid}} = dagger_ffi:connect(5000),
    ?assert(is_process_alive(Pid)),
    Mon = monitor(process, Pid),
    ?assertEqual(nil, dagger_ffi:close(Session)),
    receive {'DOWN', Mon, process, Pid, _} -> ok after 1000 -> error(session_not_closed) end,
    ?assertEqual(nil, dagger_ffi:close(Session))
end).

inherited_session_test() -> with_env(fun() ->
    os:putenv("DAGGER_SESSION_PORT", "12345"),
    os:putenv("DAGGER_SESSION_TOKEN", "inherited"),
    {ok, Session} = dagger_ffi:connect(5000),
    ?assertEqual({session, 12345, <<"inherited">>, undefined}, Session),
    ?assertEqual(nil, dagger_ffi:close(Session))
end).

invalid_session_test() -> with_env(fun() ->
    os:putenv("DAGGER_SESSION_PORT", "no-port"),
    ?assertMatch({error, _}, dagger_ffi:connect(100)),
    os:putenv("DAGGER_SESSION_TOKEN", "token"),
    ?assertMatch({error, _}, dagger_ffi:connect(100)),
    os:putenv("DAGGER_SESSION_PORT", "65536"),
    ?assertMatch({error, _}, dagger_ffi:connect(100)),
    ?assertMatch({error, _}, dagger_ffi:connect(0))
end).

startup_exit_test() -> with_env(fun() ->
    os:putenv("DAGGER_TEST_MODE", "exit"),
    ?assertEqual({error, <<"Dagger CLI exited (7)">>}, dagger_ffi:connect(5000))
end).

startup_timeout_test() -> with_env(fun() ->
    os:putenv("DAGGER_TEST_MODE", "timeout"),
    ?assertEqual({error, <<"Timed out starting Dagger session">>}, dagger_ffi:connect(100))
end).

missing_cli_test() -> with_env(fun() ->
    os:putenv("_EXPERIMENTAL_DAGGER_CLI_BIN", "/nonexistent/dagger"),
    ?assertMatch({error, _}, dagger_ffi:connect(100))
end).

cleanup_on_exception_test() ->
    Ref = make_ref(),
    ?assertException(error, intentional, dagger_ffi:with_cleanup(fun() -> error(intentional) end, fun() -> self() ! Ref end)),
    receive Ref -> ok after 100 -> error(cleanup_not_called) end.

owner_exit_test() -> with_env(fun() ->
    Parent = self(),
    Owner = spawn(fun() ->
        {ok, {session, _, _, SessionPid}} = dagger_ffi:connect(5000),
        Parent ! {session, SessionPid},
        receive stop -> ok end
    end),
    receive {session, Pid} ->
        Mon = monitor(process, Pid),
        Owner ! stop,
        receive {'DOWN', Mon, process, Pid, _} -> ok after 1000 -> error(session_leaked) end
    after 5000 -> error(session_did_not_start) end
end).

http_test_() ->
    case os:getenv("DAGGER_TEST_HTTP") of
        "1" -> fun() -> with_env(fun() ->
            os:putenv("DAGGER_TEST_MODE", "http"),
            {ok, Session} = dagger_ffi:connect(3000),
            try
    {ok, {200, Body}} = dagger_ffi:request(Session, <<"{\"query\":\"query{container{stdout}}\"}">>, 5000),
    ?assertEqual(#{<<"data">> => #{<<"container">> => #{<<"stdout">> => <<"hello from HTTP">>}}}, json:decode(Body)),
            ok
            after dagger_ffi:close(Session) end
        end) end;
        _ -> []
    end.
