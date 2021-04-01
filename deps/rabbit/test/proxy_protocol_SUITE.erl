%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2017-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(proxy_protocol_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

-compile(export_all).

-define(TIMEOUT, 5000).

all() ->
    [
        {group, sequential_tests}
    ].

groups() -> [
        {sequential_tests, [], [
            proxy_protocol,
            proxy_protocol_tls,
            proxy_protocol_v2
        ]}
    ].

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE}
    ]),
    Config2 = rabbit_ct_helpers:merge_app_env(Config1, [
        {rabbit, [
            {proxy_protocol, true}
        ]}
    ]),
    Config3 = rabbit_ct_helpers:set_config(Config2, {rabbitmq_ct_tls_verify, verify_none}),
    rabbit_ct_helpers:run_setup_steps(Config3,
        rabbit_ct_broker_helpers:setup_steps() ++
        rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
        rabbit_ct_client_helpers:teardown_steps() ++
        rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) -> Config.
end_per_group(_, Config) -> Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

proxy_protocol(Config) ->
    Port = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_amqp),
    {ok, Socket} = gen_tcp:connect({127,0,0,1}, Port,
        [binary, {active, false}, {packet, raw}]),
    ok = inet:send(Socket, "PROXY TCP4 192.168.1.1 192.168.1.2 80 81\r\n"),
    ok = inet:send(Socket, <<"AMQP", 0, 0, 9, 1>>),
    {ok, _Packet} = gen_tcp:recv(Socket, 0, ?TIMEOUT),
    ConnectionName = rabbit_ct_broker_helpers:rpc(Config, 0,
        ?MODULE, connection_name, []),
    match = re:run(ConnectionName, <<"^192.168.1.1:80 -> 192.168.1.2:81$">>, [{capture, none}]),
    gen_tcp:close(Socket),
    ok.

proxy_protocol_tls(Config) ->
    app_utils:start_applications([asn1, crypto, public_key, ssl]),
    Port = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_amqp_tls),
    {ok, Socket} = gen_tcp:connect({127,0,0,1}, Port,
        [binary, {active, false}, {packet, raw}]),
    ok = inet:send(Socket, "PROXY TCP4 192.168.1.1 192.168.1.2 80 81\r\n"),
    {ok, SslSocket} = ssl:connect(Socket, [], ?TIMEOUT),
    ok = ssl:send(SslSocket, <<"AMQP", 0, 0, 9, 1>>),
    {ok, _Packet} = ssl:recv(SslSocket, 0, ?TIMEOUT),
    ConnectionName = rabbit_ct_broker_helpers:rpc(Config, 0,
        ?MODULE, connection_name, []),
    match = re:run(ConnectionName, <<"^192.168.1.1:80 -> 192.168.1.2:81$">>, [{capture, none}]),
    gen_tcp:close(Socket),
    ok.

proxy_protocol_v2(Config) ->
    Port = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_amqp),
    {ok, Socket} = gen_tcp:connect({127,0,0,1}, Port,
        [binary, {active, false}, {packet, raw}]),
    ok = inet:send(Socket, <<13,10,13,10,0,13,10,81,85,73,84,10,33,17,0,78,158,174,6,195,10,56,72,85,132,200,22,39,32,0,63,1,0,0,0,0,33,0,7,84,76,83,118,49,46,51,37,0,7,82,83,65,50,48,52,56,36,0,10,82,83,65,45,83,72,65,50,53,54,35,0,22,84,76,83,95,65,69,83,95,50,53,54,95,71,67,77,95,83,72,65,51,56,52>>),
    ok = inet:send(Socket, <<"AMQP", 0, 0, 9, 1>>),
    {ok, _Packet} = gen_tcp:recv(Socket, 0, ?TIMEOUT),
    ConnectionName = rabbit_ct_broker_helpers:rpc(Config, 0,
        ?MODULE, connection_name, []),
    match = re:run(ConnectionName, <<"^158.174.6.195:33992 -> 10.56.72.85:5671$">>, [{capture, none}]),
    % TODO: check if SSL connection
    gen_tcp:close(Socket),
    ok.

connection_name() ->
    Pids = pg_local:get_members(rabbit_connections),
    Pid = lists:nth(1, Pids),
    {dictionary, Dict} = process_info(Pid, dictionary),
    {process_name, {rabbit_reader, ConnectionName}} = lists:keyfind(process_name, 1, Dict),
    ConnectionName.
