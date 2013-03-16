%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc validate spec, calculate next runtime
%%% @copyright Bjorn Jensen-Urstad 2012
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(crontab_time).
-compile(export_all).
-compile({no_auto_import, [now/0]}).

%%%_* Exports ==========================================================
-export([ parse_spec/1
        , find_next/2
        , now/0
        , max/1
        ]).

%%%_* Includes =========================================================
-include_lib("crontab/include/crontab.hrl").

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
parse_spec([_,_,_,_,_] = Spec) ->
  Exp   = expand_terms(Spec),
  Check = lists:append([[{U,N} || N <- L] ||
			 {U,L} <- lists:zip(units(), Exp)]),
  case try_all(fun do_validate/1, Check) of
    ok           -> {ok, Exp};
    {error, Rsn} -> {error, Rsn}
  end.

find_next(Spec, From) ->
  [U|Us] = units(),
  Nexts  = [[[{E,S}] || E <- next(U, S, fetch(U, From))] ||
	     S <- fetch(U, Spec)],
  find_next(Spec, From, Us, lists:append(Nexts)).

now() ->
  {{Y,M,D}, {Hr,Min,_Sec}} = calendar:local_time(),
  [Y, M, D, Hr, Min].

max(L) ->
  lists:max(L).

%%%_ * Internal spec validate/parse ------------------------------------
expand_terms(Spec) ->
  lists:map(fun(L) when is_list(L) -> lists:usort(L);
	       (N)                 -> [N]
	    end, Spec).

do_validate({_U, '*'})        -> ok;
do_validate({year, Y})
  when erlang:is_integer(Y),
       Y >= 0                 -> ok;
do_validate({year, _})        -> {error, year};
do_validate({month, M})
  when erlang:is_integer(M),
       M >= 1,
       M =<12                 -> ok;
do_validate({month, _})       -> {error, month};
do_validate({day, monday})    -> ok;
do_validate({day, tuesday})   -> ok;
do_validate({day, wednesday}) -> ok;
do_validate({day, thursday})  -> ok;
do_validate({day, friday})    -> ok;
do_validate({day, saturday})  -> ok;
do_validate({day, sunday})    -> ok;
do_validate({day, D})
  when erlang:is_integer(D),
       D >= 1,
       D =< 31                -> ok;
do_validate({day, _})         -> {error, day};
do_validate({hour, H})
  when erlang:is_integer(H),
       H >= 0,
       H =< 23                -> ok;
do_validate({hour, _})        -> {error, hour};
do_validate({minute, M})
  when erlang:is_integer(M),
       M >= 0,
       M =< 59                -> ok;
do_validate({minute, _})      -> {error, minute}.

try_all(F, [H|T]) ->
  case F(H) of
    ok           -> try_all(F, T);
    {error, Rsn} -> {error, Rsn}
  end;
try_all(_F, []) -> ok.

%%%_ * Internal next calculation ---------------------------------------
%% The way this works:
%% Step 1. Generate all possible dates looking at a spec and from date,
%%         what is possible is decided by the next/3 function.
%% Step 2. Filter out invalid dates and passed ones and pick the
%%         smallest one.
find_next(Spec, From, [U|Us], Dates) ->
  Nexts = [[{E,S} || E <- next(U, S, fetch(U, From))] ||
	    S <- fetch(U, Spec)],
  find_next(Spec, From, Us, [[Next|Date] || Date <- Dates,
					    Next <- lists:append(Nexts)]);

find_next(_Spec, From, [], Alldates) ->
  %% ?debug("alldates: ~p", [Alldates]),
  Fs = [ fun(Dates) -> reverse_order(Dates) end
       , fun(Dates) -> filter_invalid_ymd(Dates) end
       , fun(Dates) -> filter_invalid_day(Dates) end
       , fun(Dates) -> untag(Dates) end
       , fun(Dates) -> filter_passed(Dates, From) end
       ],
  case lists:sort(lists:foldl(fun(F, X) -> F(X) end, Alldates, Fs)) of
    [Next|_] -> {ok, Next};
    []       -> {error, no_next_found}
  end.

reverse_order(Dates) ->
  lists:map(fun(Date) -> lists:reverse(Date) end, Dates).

filter_invalid_ymd(Dates) ->
  lists:filter(fun(Date) ->
                   [{Y,_},{M,_},{D,_}] = fetch([year, month, day], Date),
                   calendar:valid_date(Y, M, D)
               end, Dates).

filter_invalid_day(Dates) ->
  lists:filter(fun(Date) ->
		   [{Y,_},{M,_},{D,Ds}] = fetch([year, month, day], Date),
		   case erlang:is_atom(Ds) andalso Ds =/= '*' of
		     true  -> Ds =:= day_of_the_week(Y,M,D);
		     false -> true
		   end
	       end, Dates).

untag(Dates) ->
  lists:map(fun(Date) ->
		{L, _} = lists:unzip(Date),
		L
	    end, Dates).

filter_passed(Dates, From) ->
  lists:filter(fun(Date) -> Date > From end, Dates).

next(year,   '*', Y ) -> [Y, Y+1, Y+2, Y+3, Y+4];
next(year,   Y,   _ ) -> [Y];
next(month,  '*', 12) -> [12, 1];
next(month,  '*', M ) -> [M, M+1, 1];
next(month,  M,   _ ) -> [M];
next(day,    '*', 28) -> [1, 28, 29];
next(day,    '*', 29) -> [1, 29, 30];
next(day,    '*', 30) -> [1, 30, 31];
next(day,    '*', 31) -> [1, 31];
next(day,    '*', D ) -> [1, D, D+1];
next(day,    S,   _ )
  when is_atom(S)     -> lists:seq(1, 31);
next(day,    S,   _ ) -> [S];
next(hour,   '*', 23) -> [0, 23];
next(hour,   '*', H ) -> [0, H, H+1];
next(hour,   H,   _ ) -> [H];
next(minute, '*', 59) -> [0];
next(minute, '*', M ) -> [0, M+1];
next(minute, M,   _ ) -> [M].

fetch(year,   [Y,_,_,_,_]       ) -> Y;
fetch(month,  [_,M,_,_,_]       ) -> M;
fetch(day,    [_,_,D,_,_]       ) -> D;
fetch(hour,   [_,_,_,H,_]       ) -> H;
fetch(minute, [_,_,_,_,M]       ) -> M;
fetch(Us,     [_,_,_,_,_] = Spec) -> [fetch(U, Spec) || U <- Us].

units() -> [year, month, day, hour, minute].

day_of_the_week(Y, M, D) ->
  day_of_the_week(calendar:day_of_the_week(Y, M, D)).

day_of_the_week(1) -> monday;
day_of_the_week(2) -> tuesday;
day_of_the_week(3) -> wednesday;
day_of_the_week(4) -> thursday;
day_of_the_week(5) -> friday;
day_of_the_week(6) -> saturday;
day_of_the_week(7) -> sunday.

%%%_* Tests ============================================================
-ifdef(TEST).
%% -include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(skew, 10).
every_day_test() ->
  Spec = ['*', '*', '*', 0, 0],
  Diff = 86400,
  iterate(Spec, Diff).

every_week_test_() ->
  {timeout, 30,
   fun() ->
       lists:foreach(fun(D) ->
			 Spec = ['*', '*', day_of_the_week(D), 0, 0],
			 Diff = 86400 * 7,
			 iterate(Spec, Diff)
		     end, lists:seq(1, 7))
   end}.

every_15m_test() ->
  Spec = ['*', '*', '*', '*', [0, 15, 30, 45]],
  Diff = 3600 div 4,
  iterate(Spec, Diff).

every_hour_test() ->
  Spec = ['*', '*', '*', '*', 0],
  Diff = 3600,
  iterate(Spec, Diff).

-define(steps, 500).
iterate(Spec, Diff) ->
  {ok, PSpec} = parse_spec(Spec),
  {ok, Next}  = find_next(PSpec, now()),
  do_iterate(PSpec, Diff, Next, ?steps).

do_iterate(_, _, _, 0) -> ok;
do_iterate(PSpec, Diff, [Y1,M1,D1,H1,Min1] = Prev, N) ->
  {ok, [Y2,M2,D2,H2,Min2]=Next} = find_next(PSpec, Prev),
  GSecs1 = calendar:datetime_to_gregorian_seconds({{Y1,M1,D1},{H1,Min1,0}}),
  GSecs2 = calendar:datetime_to_gregorian_seconds({{Y2,M2,D2},{H2,Min2,0}}),
  RDiff = GSecs2 - GSecs1,
  true = RDiff > (Diff-?skew) andalso RDiff < Diff+?skew,
  do_iterate(PSpec, Diff, Next, N-1).

next_test() ->
  lists:foreach(fun({Spec, Now, Expected}) ->
                    {ok, PSpec} = parse_spec(Spec),
                    ?assertEqual({ok, Expected}, find_next(PSpec, Now))
                end, tests()),
  ok.

tests() ->
  %% {Spec, Now, Expected}
  [ {['*',  2, 29,     20,  0 ],  [2012, 3,  1,0,0],  [2016,2,29,20,0]}
  , {['*',  1, friday, 0,   0 ],  [2012, 1,  1,1,43], [2012,1,6,0,0]}
  , {[2014, 9, 15,     '*', 20],  [2013, 11, 28, 12, 3], [2014,9,15,0,20]}
  , {['*',   2, '*',    0,   0 ], [2012, 2,  28, 0,  0], [2012, 2, 29, 0, 0]}
  , {['*',  '*', 30,  '*',  '*'],[2012, 4,  30, 0, 59], [2012, 4, 30, 1, 0]}
  ].

-else.

-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
