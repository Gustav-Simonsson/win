%%%-------------------------------------------------------------------
%%% @author Niclas Axelsson <burbas@Niclass-MacBook-Pro.local>
%%% @copyright (C) 2012, Niclas Axelsson
%%% @doc
%%% Handles entities; unregisters and registers entities such as mobs, items and
%%% players, and broadcasts events to these entities. 
%%% @end
%%% Created :  8 Jul 2012 by Niclas Axelsson <burbas@Niclass-MacBook-Pro.local>
%%%-------------------------------------------------------------------
-module(browserquest_srv_entity_handler).

-behaviour(gen_server).

-include("../include/browserquest.hrl").
%% API
-export([
	 start_link/0,
	 register/4,
	 register_static/3,
	 unregister/1,
	 event/3,
	 move_zone/2,
	 make_zone/2,
	 generate_id/1,
	 calculate_dmg/2,
	 get_target/1
	]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {
	  zones :: dict(),
	  targets :: dict(),
          mobs,
          staticEntities
	 }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

register(Zone, Type, Id, SpawnInfo) ->
    Pid = self(),
    gen_server:call(?MODULE, {register, Pid, Zone, Id}),
    event(Zone, Type, SpawnInfo).

register_static(Zone, Type, SpawnInfo) ->
    Pid = self(),
    gen_server:call(?MODULE, {register, {static, Pid}, Zone}),
    event(Zone, Type, SpawnInfo).

unregister(Zone) ->
    Pid = self(),
    gen_server:call(?MODULE, {unregister, Pid, Zone}).

event(Zone, Type, Message) ->
    Pid = self(),
    gen_server:call(?MODULE, {event, Pid, Zone, Type, Message}).

get_target(Target) ->
    gen_server:call(?MODULE, {get_target, Target}).

move_zone(OldZone, NewZone) ->
    Pid = self(),
    gen_server:call(?MODULE, {unregister, Pid, OldZone}),
    gen_server:call(?MODULE, {register, Pid, NewZone}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([]) ->
    Args = [fun add_mob/1, browserquest_srv_map:get_attribute("mobAreas")],
    erlang:spawn(lists, foreach, Args),
    {ok, #state{zones = dict:new(), targets = dict:new()}}.

handle_call({register, Pid, Zone, Id}, _From, 
            State = #state{targets = Targets,zones = Zones}) ->
    UpdatedZones = 
        dict:update(Zone, fun(Nodes) -> [Pid|Nodes] end, [Pid], Zones),
    UpdatedTargets = dict:store(Id, Pid, Targets),
    {reply, ok, State#state{zones = UpdatedZones, targets = UpdatedTargets}};

handle_call({unregister, Pid, Zone}, _From, State = #state{zones = Zones}) ->
    Update = fun(Nodes) -> [ X || X <- Nodes, X /= Pid, X /= {static, Pid}] end,
    UpdatedZones = dict:update(Zone, Update, [], Zones),
    {reply, ok, State#state{zones = UpdatedZones}};

handle_call({get_target, Target}, _From, State = #state{targets = Targets}) ->
    Reply = dict:find(Target, Targets),
    {reply, Reply, State};

handle_call({event, Pid, Zone, Type, Message}, _From,
            State = #state{zones = Zones}) when is_pid(Pid) ->
    case dict:find(Zone, Zones) of
	{ok, Nodes} ->
	    [gen_server:cast(Node, {event, Pid, Type, Message}) 
             || Node <- Nodes, Node /= Pid, Node /= {static, Pid}];
	_ ->
	    []
    end,
    {reply, ok, State};

handle_call({event, Target, _Zone, Type, Message}, _From, 
            State = #state{targets = Targets}) ->
    case dict:find(Target, Targets) of
	{ok, Pid} ->
	    gen_server:cast(Pid, {event, Pid, Type, Message});
	_ ->
	    ok
    end,
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
ensure_bin(Int) when is_integer(Int) ->
    ensure_bin(erlang:integer_to_list(Int));
ensure_bin(List) when is_list(List) ->
    erlang:list_to_binary(List);
ensure_bin(Bin) when is_binary(Bin) ->
    Bin.

%%%===================================================================
%%% Exported functions
%%%===================================================================
make_zone(PosX, PosY) ->
    ZoneString = erlang:integer_to_list((( PosX div 28)+1)*((PosY div 12)+1)),
    ensure_bin("ZONE"++ZoneString).

generate_id(InitialValue) when is_list(InitialValue) ->
    random:seed(erlang:now()),
    erlang:list_to_integer(InitialValue ++ erlang:integer_to_list(random:uniform(1000000))).

calculate_dmg(TargetArmor, SourceWeapon) ->
    random:seed(erlang:now()),
    Dealt = SourceWeapon * (5+random:uniform(5)),
    Absorbed = TargetArmor * (1+random:uniform(2)),
    case Dealt-Absorbed of
	Positive when Positive > 0 ->
	    Positive;
	_Neg ->
	    random:uniform(3)
    end.

add_mob(#mobarea{type = Type, x = X, y = Y}) ->
    browserquest_srv_mob_sup:add_child(Type, X, Y).
