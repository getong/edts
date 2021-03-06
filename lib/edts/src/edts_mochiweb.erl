%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Top-level edts supervisor.
%%% @end
%%% @author Thomas Järvstrand <tjarvstrand@gmail.com>
%%% @copyright
%%% Copyright 2012 Thomas Järvstrand <tjarvstrand@gmail.com>
%%%
%%% This file is part of EDTS.
%%%
%%% EDTS is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU Lesser General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% EDTS is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public License
%%% along with EDTS. If not, see <http://www.gnu.org/licenses/>.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-module(edts_mochiweb).

-export([start_link/0,
         handle_request/1]).

%%%_* Includes =================================================================

-include_lib("kernel/include/logger.hrl").

%%%_* Defines ==================================================================

-define(EDTS_PORT_DEFAULT, "4587").

%%%_* Types ====================================================================
%%%_* API ======================================================================

start_link() ->
  mochiweb_http:start_link([{name, ?MODULE},
                            {loop, fun ?MODULE:handle_request/1},
                            {port, configured_port()}]).


handle_request(Req) ->
  try
    case mochiweb_request:get(method, Req) of
      'POST' ->
        case do_handle_request(Req) of
          ok ->
            ok(Req);
          {ok, Data} ->
            ok(Req, Data);
          {error, {not_found, Term}} ->
            error(Req, not_found, Term);
          {error, {bad_gateway, Term}} ->
            error(Req, bad_gateway, Term)
        end;
      _ ->
        error(Req, method_not_allowed, [])
    end
  catch
    Class:Reason:Stack ->
      error(Req,
            internal_server_error,
            [{class, format_term(Class)},
             {reason, format_term(Reason)},
             {stack_trace, format_term(Stack)}])
  end.

format_term(Term) ->
  list_to_binary(lists:flatten(io_lib:format("~p", [Term]))).

do_handle_request(Req) ->
  Path = mochiweb_request:get(path, Req),
  case [list_to_atom(E) || E <- string:tokens(Path, "/")] of
    [Command] ->
      edts_cmd:execute(Command, get_input_context(Req));
    [lib, Plugin, Command] ->
      edts_plugins:execute(Plugin, Command, get_input_context(Req));
    _ ->
      {error, {not_found, [{path, list_to_binary(Path)}]}}
  end.

get_input_context(Req) ->
  case mochiweb_request:recv_body(Req) of
    undefined ->
      orddict:new();
    <<"null">> ->
      orddict:new();
    Body ->
      orddict:from_list(
        decode_element(
          mochijson2:decode(
            binary_to_list(Body), [{format, proplist}])))
  end.

decode_element([{_, _}|_] = Element) ->
  lists:map(fun({K, V}) ->
                {list_to_atom(binary_to_list(K)), decode_element(V)}
            end,
            Element);
decode_element(Element) when is_list(Element) ->
  lists:map(fun decode_element/1, Element);
decode_element(Element) when is_binary(Element) ->
  binary_to_list(Element);
decode_element(Element) ->
  Element.

ok(Req) ->
  ok(Req, undefined).

ok(Req, Data) ->
  respond(Req, 200, Data).

error(Req, not_found, Data) ->
  error(Req, 404, "Not Found", Data);
error(Req, method_not_allowed, Data) ->
  error(Req, 405, "Method Not Allowed", Data);
error(Req, internal_server_error, Data) ->
  error(Req, 500, "Internal Server Error", Data);
error(Req, bad_gateway, Data) ->
  error(Req, 502, "Bad Gateway", Data).

error(Req, Code, Message, Data) ->
  Body = [{code,    Code},
          {message, list_to_binary(Message)},
          {data,    Data}],
  respond(Req, Code, Body).

respond(Req, Code, Data) ->
  Headers = [{"Content-Type", "application/json"}],
  BodyString = case Data of
                 undefined -> "";
                 _         -> mochijson2:encode(Data)
               end,
  mochiweb_request:respond({Code, Headers, BodyString}, Req).

%%%_* Internal functions =======================================================

configured_port() ->
  Port = os:getenv("EDTS_PORT", ?EDTS_PORT_DEFAULT),
  ?LOG_DEBUG("Using EDTS port ~p from file.", [Port]),
  list_to_integer(Port).

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
