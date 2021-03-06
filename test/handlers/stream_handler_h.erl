%% This module behaves differently depending on a specific header.

-module(stream_handler_h).
-behavior(cowboy_stream).

-export([init/3]).
-export([data/4]).
-export([info/3]).
-export([terminate/3]).
-export([early_error/5]).

-record(state, {
	pid,
	test
}).

init(StreamID, Req, Opts) ->
	Pid = list_to_pid(binary_to_list(cowboy_req:header(<<"x-test-pid">>, Req))),
	Test = binary_to_atom(cowboy_req:header(<<"x-test-case">>, Req), latin1),
	State = #state{pid=Pid, test=Test},
	Pid ! {Pid, self(), init, StreamID, Req, Opts},
	{init_commands(StreamID, Req, State), State}.

init_commands(_, _, #state{test=crash_in_init}) ->
	error(crash);
init_commands(_, _, #state{test=crash_in_data}) ->
	[];
init_commands(_, _, #state{test=crash_in_info}) ->
	[];
init_commands(_, _, #state{test=crash_in_terminate}) ->
	[{response, 200, #{<<"content-length">> => <<"12">>}, <<"Hello world!">>}, stop];
init_commands(_, _, #state{test=crash_in_early_error}) ->
	error(crash);
init_commands(_, _, State=#state{test=shutdown_on_stream_stop}) ->
	Spawn = init_process(false, State),
	[{headers, 200, #{}}, {spawn, Spawn, 5000}, stop];
init_commands(_, _, State=#state{test=shutdown_on_socket_close}) ->
	Spawn = init_process(false, State),
	[{headers, 200, #{}}, {spawn, Spawn, 5000}];
init_commands(_, _, State=#state{test=shutdown_timeout_on_stream_stop}) ->
	Spawn = init_process(true, State),
	[{headers, 200, #{}}, {spawn, Spawn, 2000}, stop];
init_commands(_, _, State=#state{test=shutdown_timeout_on_socket_close}) ->
	Spawn = init_process(true, State),
	[{headers, 200, #{}}, {spawn, Spawn, 2000}];
init_commands(_, _, State=#state{test=terminate_on_stop}) ->
	[{response, 204, #{}, <<>>}];
init_commands(_, _, _) ->
	[{headers, 200, #{}}].

init_process(TrapExit, #state{pid=Pid}) ->
	Self = self(),
	Spawn = spawn_link(fun() ->
		process_flag(trap_exit, TrapExit),
		Pid ! {Pid, Self, spawned, self()},
		receive {Pid, ready} -> ok after 1000 -> error(timeout) end,
		Self ! {self(), ready},
		receive after 5000 ->
			Pid ! {Pid, Self, still_alive, self()}
		end
	end),
	receive {Spawn, ready} -> ok after 1000 -> error(timeout) end,
	Spawn.

data(_, _, _, #state{test=crash_in_data}) ->
	error(crash);
data(StreamID, IsFin, Data, State=#state{pid=Pid}) ->
	Pid ! {Pid, self(), data, StreamID, IsFin, Data, State},
	{[], State}.

info(_, Resp={response, _, _, _}, State) ->
	{[Resp], State};
info(_, crash, #state{test=crash_in_info}) ->
	error(crash);
info(StreamID, Info, State=#state{pid=Pid}) ->
	Pid ! {Pid, self(), info, StreamID, Info, State},
	case Info of
		please_stop -> {[stop], State};
		_ -> {[], State}
	end.

terminate(StreamID, Reason, State=#state{pid=Pid, test=crash_in_terminate}) ->
	Pid ! {Pid, self(), terminate, StreamID, Reason, State},
	error(crash);
terminate(StreamID, Reason, State=#state{pid=Pid}) ->
	Pid ! {Pid, self(), terminate, StreamID, Reason, State},
	ok.

%% This clause can only test for early errors that reached the required headers.
early_error(StreamID, Reason, PartialReq, Resp, Opts) ->
	Pid = list_to_pid(binary_to_list(cowboy_req:header(<<"x-test-pid">>, PartialReq))),
	Pid ! {Pid, self(), early_error, StreamID, Reason, PartialReq, Resp, Opts},
	case cowboy_req:header(<<"x-test-case">>, PartialReq) of
		<<"crash_in_early_error",_/bits>> -> error(crash);
		_ -> Resp
	end.
