%% @author Gabriel Tholsg�rd <gath5951@student.uu.se>
%%   [www.csproj13.student.it.uu.se]
%% @version 1.0
%% @copyright [Copyright information]
%%
%% @doc == virtual_stream_process_supervisor ==
%% This module represents a virtual stream process supervisor which
%% initializes all virtual stream processes and puts them under its
%% supervision. 
%%
%% @end

-module(virtual_stream_process_supervisor).

-include_lib("erlastic_search.hrl").
-include_lib("json.hrl").
-include_lib("common.hrl").
-include("debug.hrl").

-behaviour(supervisor).
-export([init/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0, start_processes/0, add_child/3]).




%% start_link/0
%% ====================================================================
%% @doc
%% Function: start_link/0
%% Purpose: Initializes as a supervisor process for virtual streams.
%% Return: {ok, Pid} | ignore | {error, {already_started, Pid}} |
%%		   {error, {shutdown, Reason}} | {error, Reason}.
%% Side effect: Starts a supervisor process for virtual streams.
%% @end
-spec start_link() -> Startlink_ret when
	Startlink_ret :: {ok, pid()}
	               | ignore
	               | {error, Startlink_err},
	Startlink_err :: {already_started, pid()}
    	           | {shutdown, term()}
        	       | term().
%% ====================================================================
start_link() ->
	supervisor:start_link({local, vstream_sup}, ?MODULE, []).



%% start_processes/0
%% ====================================================================
%% @doc
%% Function: start_processes/0
%% Purpose: Load and start all virtual stream processes under supervison.
%% Return: ok | {error, Reason}.
%% Side effects: Starts several virtual stream processes.
%% @end
-spec start_processes() -> ok | {error, string()}.
%% ====================================================================
start_processes() ->
	case whereis(vstream_sup) of
		undefined ->
			{error, "Start the supervisor first"};
		_ ->
			case erlastic_search:search(?ES_INDEX, "virtual_stream", "*") of
				{error, {Code, Body}} ->
					ErrorString = api_help:generate_error(Body, Code),
					{error, ErrorString};
				{ok, JsonStruct} ->
				    VStreamList = lib_json:get_field(JsonStruct, "hits.hits"),
				    MapFunc =
				    	fun(List) ->
				    		[{stream, binary_to_list(X)} || X <- List]
				    	end,
				    %% Structure: [{VId, Function, [{stream, SId}, ... ]}, ...].
				    ProcessInfoList =
				    	[{binary_to_list(lib_json:get_field(X, "_id")),
				    	  list_to_atom( binary_to_list(
				    	  	lib_json:get_field(X, "_source.function[0]") ) ),
				    	  MapFunc(
				    	  	lib_json:get_field(X, "_source.streams_involved") )}
				    	  || X <- VStreamList],
				    _ = [supervisor:start_child(vstream_sup, [Id, Input, Func])
				    	 || {Id, Func, Input} <- ProcessInfoList],
				    ok
			end
	end.




%% add_child/3
%% ====================================================================
%% @doc
%% Function: add_child/3
%% Purpose: Add a virtual stream process under supervision.
%% Args: Id - The id of the virtual stream to start
%%       InputIds - The list of streams to subscribe to, in the form:
%%                  [{Type, SId}, ...] where SId is the Id of the
%%                  stream and Type is either the atom stream or vstream.
%%       Function - The aggregation function to apply 
%% Return: ok | {error, Reason}.
%% Side effects: Starts a virtual stream processes under supervision.
%% @end
-spec add_child(Id :: string(), InputIds :: [StreamInfo], Function :: atom()) ->
	ok | {error, string()} when
		StreamInfo :: {Type, Id :: string()},
		Type :: stream | vstream.
%% ====================================================================
add_child(Id, InputIds, Function) ->
	case whereis(vstream_sup) of
		undefined ->
			{error, "Start the supervisor first"};
		_ ->
			_ = supervisor:start_child(vstream_sup, [Id, InputIds, list_to_atom(binary_to_list(lists:nth(1, Function)))]),
			ok
	end.




%% ====================================================================
%% Behavioural functions 
%% ====================================================================

%% init/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/supervisor.html#Module:init-1">supervisor:init/1</a>
-spec init(Args :: term()) -> Result when
	Result :: {ok, {SupervisionPolicy, [ChildSpec]}} | ignore,
	SupervisionPolicy :: {RestartStrategy, MaxR :: non_neg_integer(), MaxT :: pos_integer()},
	RestartStrategy :: one_for_all
					 | one_for_one
					 | rest_for_one
					 | simple_one_for_one,
	ChildSpec :: {Id :: term(), StartFunc, RestartPolicy, Type :: worker | supervisor, Modules},
	StartFunc :: {M :: module(), F :: atom(), A :: [term()] | undefined},
	RestartPolicy :: permanent
				   | transient
				   | temporary,
	Modules :: [module()] | dynamic.
%% ====================================================================
init([]) ->
    {ok,{{simple_one_for_one,5,60},
    	[{gen_virtual_stream_process,
    	  {gen_virtual_stream_process, start_link, []},
    	  transient, brutal_kill, worker, [gen_virtual_stream_process]}
		]}}.



%% ====================================================================
%% Internal functions
%% ====================================================================


