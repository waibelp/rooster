-module(rooster_sup).
-behaviour(supervisor).

-export([start_link/1, upgrade/0]).
-export([init/1]).

%% ===============
%%% API functions
%% ===============
start_link([SrvConf, State]) ->
  ISrvConf = rooster_adapter:config(SrvConf),
  supervisor:start_link({local, ?MODULE}, ?MODULE, [ISrvConf, State]).

%% ===============
%%% Supervisor callbacks
%% ===============
init([Conf, State]) ->
  WebSpecs = web_specs(rooster_web, Conf),
  MiddlewareSpecs = middleware_specs(State),
  StateSpecs = state_specs(State),
  rooster_deps:ensure(),
  {ok, {{one_for_one, 10, 10}, [MiddlewareSpecs, StateSpecs, WebSpecs]}}.

upgrade() ->
  {ok, {_, Specs}} = init([]),
  Old = sets:from_list(
    [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
  New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
  Kill = sets:subtract(Old, New),

  sets:fold(fun(Id, ok) ->
    supervisor:terminate_child(?MODULE, Id),
    supervisor:delete_child(?MODULE, Id),
    ok
            end, ok, Kill),

  [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
  ok.

%% ===============
%%% Internal functions
%% ===============
web_specs(Mod, #{ip := Ip, port := Port, static_path := Sp, ssl := Ssl, ssl_opts := Ssl_opts}) ->
  WebConfig = [{ip, Ip},
    {port, Port},
    {docroot, rooster_deps:local_path(Sp, ?MODULE)},
    Ssl, Ssl_opts],
  {Mod, {Mod, start, [WebConfig]}, permanent, 5000, worker, dynamic}.

state_specs(State) ->
  #{id       => rooster_state,
    start    => {rooster_state, start_link, [State]},
    restart  => permanent,
    shutdown => brutal_kill,
    type     => worker,
    modules  => []}.

middleware_specs(#{middleware := Middleware}) ->
  #{id       => rooster_middleware,
    start    => {rooster_middleware, start_link, [Middleware]},
    restart  => permanent,
    shutdown => brutal_kill,
    type     => worker,
    modules  => []}.