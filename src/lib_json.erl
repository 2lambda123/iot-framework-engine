%% @author Tommy Mattsson, Georgios Koutsoumpakis [www.csproj13.student.it.uu.se]
%% @copyright [Copyright information]
%% @version 1.0
%% @doc == Library for creating, reading, updating, and deleting fields in JSON objects ==
%% @end
-module(lib_json).
-include("erlson.hrl").
-include("json.hrl").
%% ====================================================================
%% API functions - Exports
%% ====================================================================
-export([add_value/3,
	 add_value_in_list/2,
	 decode/1, 
	 encode/1, 
	 field_value_exists/3, 
	 get_field/2, 
	 get_fields/2,
	 get_field_value/3, 
	 replace_field/3,
	 rm_field/2,
	 set_attr/2,
	 to_string/1]).
%% ====================================================================
%% Specialized functions - Exports
%% ====================================================================
-export([get_and_add_id/1, 
	 get_list_and_add_id/1
	]).
-include("misc.hrl").
%% ====================================================================
%% Type definitions
%% ====================================================================
%% @type attr() = atom() | string()
-type attr() :: atom() | string().
%% @type field() = json_string() | mochijson()
-type field() :: atom() | string() | [atom()].
%% @type json() = json_string() | mochijson()
-type json() :: json_string() | mochijson().
%% @type json_string() = string()
-type json_string() :: string().
%% @type json_input_value() = atom() | binary() | integer() | string() | json() | [json()]
-type json_input_value() :: atom() | binary() | integer() | string() | json() | [json()].
%% @type json_output_value() = integer() | string() | json_string() | [json_output_value()]
-type json_output_value() :: integer() | string() | json_string() | [json_output_value()].
%% @type mochijson() = tuple() 
-type mochijson() :: tuple(). 


%% ====================================================================
%% API functions
%% ====================================================================
%% @doc
%% TODO Should be removed because add_value/3 provides the proper functionality
%% @end
add_value_in_list(List, Value) when is_list(List) ->
	V = decode(Value),
	A= {struct,[{<<"streams">>, [V | List]}]},
	A.

%% @doc 
%% Adds a new value to a field with the name 'Field' and the value 'Value' to a JSON object.
%% If the field doesn't exist then it is added, but only if the Field path is valid. This 
%% means that it can not add nested fields, but it can add a field either to the root or
%% inside another attribute.
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Field = "attr2".
%% > Value = "value2".
%% > lib_json:add_value(Json, Field, Value).
%% "{\"attr1\":\"value1\", \"attr2\":\"value2\"}"
%% '''
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Field = "attr2.attr3".
%% > Value = "value2".
%% > lib_json:add_value(Json, Field, Value).
%% "{\"attr1\":\"value1\"}"
%% '''
%% @end
-spec add_value(Json::json(), Field::field(),Value::json_input_value()) -> json_string().
add_value(Json, Field, Value)  ->
    NewJson  = parse_json(Json),
    Attrs    = parse_attr(Field),
    NewValue = parse_value(Value),
    format_output(add_value_internal(NewJson, Attrs, NewValue)).

%% @doc 
%% Decodes a json object into mochijson format.
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > lib_json:decode(Json).
%% {struct,[{<<"attr1">>,<<"value1">>}]}
%% '''
%% @end
-spec decode(Json::json_string()) -> mochijson().
decode(Json) when is_list(Json) ->
     mochijson2:decode(Json).

%% @doc
%% Encodes a json object into an iolist() that can easily be converted into a string.
%%
%% Example:
%% ```
%% > Json = {struct,[{<<"attr1">>,<<"value1">>}]}".
%% > lib_json:encode(Json).
%% [123,[34,<<"attr1">>,34],58,[34,<<"value1">>,34],125]
%% '''
%% @end
-spec encode(Json::json()) -> iolist().
encode(Json) when is_tuple(Json)->
    Encoder = mochijson2:encoder([{utf8, true}]),
    Encoder(Json);
encode(Json) when is_list(Json) ->
    JsonObj = decode(Json),
    Encoder = mochijson2:encoder([{utf8, true}]),
    Encoder(JsonObj).

%% @doc
%% Check if a specific field with a specific value exists in a JSON object.
%% Handles wildcard searches for fields (not wildcard for values.
%% 
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Query = "attr1".
%% > lib_json:field_value_exists(Json, Query, Value).
%% true
%% '''
%% @end
-spec field_value_exists(Json::json(), Query::string(), Value::json_input_value()) -> boolean().
field_value_exists(Json, Query, Value) ->
    case get_field_value(Json, Query, Value) of
	Value ->
	    true;
	undefined ->
	    false
    end.

%% @doc
%% Get the value at a certain field in a JSON object.
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Query = "attr1".
%% > lib_json:get_field(Json, Query).
%% "value1"
%% '''
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Query = "attr2".
%% > lib_json:get_field(Json, Query).
%% undefined
%% '''
%% @end
-spec get_field(Json::json(), Query::string()) -> json_output_value().
get_field(Json, Query) ->
    erlang:display("11##################################"),
    erlang:display(Json),
    NewJson  = parse_json(Json),
    erlang:display("22##################################"),
    Attrs    = parse_attr(Query),
    format_output(get_field_internal(NewJson, Attrs)).


%% @doc
%% Get the values for a list of specified fields.
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\",\"attr2\":\"value2\"}".
%% > Fields = ["attr1", "attr2"].
%% > lib_json:get_fields(Json, Fields).
%% ["value1", "value2"]
%% '''
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\",\"attr2\":\"value2\"}".
%% > Fields = ["attr1", "attr3"].
%% > lib_json:get_fields(Json, Fields).
%% ["value1", undefined]
%% '''
%% @end
-spec get_fields(Json::json(), Fields::[field()]) -> json_output_value().
get_fields(_Json, []) ->
    [];
get_fields(Json, [Field|Tl]) ->
    Result = get_field(Json, Field),
    [Result | get_fields(Json, Tl)].
    
%% @doc
%% Get a certain value of a certain field. Returns 'undefined' if there is no field with that value.
%% 
%% Example:
%% ```
%% > Json = "{\"attr1\": [{\"attr2\":\"value1\"},{\"attr2\":\"value2\"}]}".
%% > Query = "attr1[*].attr2".
%% > Value = "value2".
%% > lib_json:get_field_value(Json, Query, Value).
%% "value2"
%% '''
%% @end
-spec get_field_value(Json::json(), Query::field(), Value::json_input_value()) -> json_output_value().
get_field_value(Json, Query, Value) ->
    QueryParts = find_wildcard_fields(Query),
    try field_recursion(Json, QueryParts, Value) of
	Value ->
	    Value;
	_ ->
	    undefined
    catch
	%% I could use only a catch all clause, but I left these here to show how 
	%% try catch throw works in Erlang
	error:{badfun, _} -> throw_incorrect_syntax(Query);
	error:{case_clause, _} -> throw_incorrect_syntax(Query);
	error:function_clause -> throw_incorrect_syntax(Query);
	_:_ -> throw_incorrect_syntax(Query)
    end.

%% @doc
%% Replaces the value of a field 'Query' with 'Value' in a JSON object
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Query = "attr1".
%% > Value = <<"poff">>.
%% > lib_json:replace_field(Json, Query, Value).
%% "{\"attr1\":\"poff\"}"
%% '''
%% @end
-spec replace_field(Json::json(), Query::field(), Value::json_input_value()) -> json_output_value().
replace_field(Json, Query, Value) ->
    NewJson  = parse_json(Json),
    Attrs    = parse_attr(Query),
    NewValue = parse_value(Value),
    format_output(replace_field_internal(NewJson, Attrs, NewValue)).

%% @doc
%% Removes the field 'Query' from a JSON object
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Query = "attr1".
%% > lib_json:rm_field(Json, Query).
%% "{}"
%% '''
%% @end
-spec rm_field(Json::json(), Query::field()) -> json_output_value().
rm_field(Json, Query)  ->
    NewJson  = parse_json(Json),
    Attrs    = parse_attr(Query),
    format_output(rm_field_internal(NewJson, Attrs)).

%% @doc
%% Sets a json attribute 'Attr' to 'Value'. This function is only for creating 
%% a proper JSON object with one attribute 'Attr' in it set to 'Value'. 
%%
%% For adding add an attribute and/or value see: <a href="#add_value-3">add_value/3</a>
%%
%% For replaceing a value see: <a href="#replace_field-3">replace_value/3</a>
%%
%% Example:
%% ```
%% > Json = "{\"attr1\":\"value1\"}".
%% > Attr = "attr1".
%% > Value = value
%% > lib_json:set_attr(Attr, Value).
%% "{\"attr1\":\"value\"}"
%% '''
%% @end
-spec set_attr(Attr::attr(), Value::json_input_value()) -> json_output_value().
set_attr(Attr, Value) ->
    add_value("{}", Attr, Value).



%% @doc
%% Converts a mochijson structure or a mochijson encoded structure into a string
%%
%% Example:
%% ```
%% > Json = {struct,[{<<"attr1">>,<<"value1">>}]}.
%% > lib_json:to_string(Json).
%% "{\"attr1\":\"value\"}"
%% '''
%% @end
-spec to_string(Json::mochijson() | iolist()) -> json_string().
to_string(Json) when is_tuple(Json) ->
    to_string(encode(Json));
to_string(Json) when is_binary(Json) ->
    binary:bin_to_list(Json);
to_string(Json) ->
    %% Flattens a list and converts the entire thing into a binary.
    BinaryJson = binary:list_to_bin(Json),
    %% Converts the binary into a string.
    binary:bin_to_list(BinaryJson).


%% ====================================================================
%% Specialized functions
%% ====================================================================
%% @doc 
%% Gets the '_id' from the root, gets the '_source'. Adds _id as 
%% id' in _source and return the new JSON object.
%%
%% TODO Move to api_help
%% @end 
-spec get_and_add_id(JsonStruct::mochijson()) -> json_output_value().
get_and_add_id(JsonStruct) ->
    %% erlang:display("+++++++++++++++++++111+++++++++++++++++++++"),
    %% erlang:display(to_string(JsonStruct)),
    Id  = get_field(JsonStruct, "_id"),
    %% erlang:display(Id),
    %% erlang:display("+++++++++++++++++++222+++++++++++++++++++++"),
    SourceJson  = get_field(JsonStruct, "_source"),
    %% erlang:display(SourceJson),
    %% erlang:display("+++++++++++++++++++444+++++++++++++++++++++"),
    P = add_value(SourceJson, "id", binary:list_to_bin(Id)),
    %% erlang:display(P),
    %% erlang:display("+++++++++++++++++++333+++++++++++++++++++++"),
    P
    .

%% @doc 
%% Get the search results and performs get_and_add_id/1 on each
%% elements in the result list.
%%
%% TODO Move to api_help
%% @end 
-spec get_list_and_add_id(JsonStruct::mochijson()) -> json_string().
get_list_and_add_id(JsonStruct) ->
    %% erlang:display("+++++++++++++++++++444+++++++++++++++++++++"),
    %% erlang:display(to_string(JsonStruct)),
    HitsList = get_field(JsonStruct, "hits.hits"),
    AddedId = lists:map(fun(X) -> get_and_add_id(X) end, HitsList),
    %% erlang:display("+++++++++++++++++++555+++++++++++++++++++++"),
    P = set_attr(hits, AddedId),
    %% erlang:display(P),
    %% erlang:display("+++++++++++++++++++666+++++++++++++++++++++"),
    P.


%% ====================================================================
%% Internal functions
%% ====================================================================
%% @doc
%% @hidden
%% Function: add_value_internal/3
%% @end
add_value_internal(Json, Attrs, Value) ->
    try erlson:get_value(Attrs, Json) of
	undefined ->
	    %% erlang:display("undefined Json"),
	    ?erlson_default(erlson:store(Attrs, Value, Json), Json);
	List when is_list(List) ->
	    %% erlang:display("List Json"),
	    NewList = lists:sort([Value | List]),
	    erlson:store(Attrs, NewList, Json);
	_ -> 
	    %% erlang:display("non-list Json"),
	    Json
    catch
	_:_ ->
	    Json
    end.

%% @doc
%% @hidden
%% Function: field_recursion/3
%% Purpose: Handles recursion over the specific fields in a json object 
%% Returns: Either the found value or 'false'
%% @end
field_recursion(Json, QueryParts, Value) ->
    field_recursion(Json, QueryParts, Value, "").

%% @doc
%% @hidden
%% Function: field_recursion/4
%% Purpose: Handles recursion over the specific fields in a json object 
%% Returns: Either the found value or 'false'
%% @end
field_recursion(Json, [{wildcard, Field} | Rest], Value, Query) ->
    case get_field_max_index(Json, Field) of
	N when is_integer(N) ->
	    case index_recursion(Json, [{wildcard, Field, N}| Rest], Value, Query) of
		Value ->
		    Value;
		R ->
		    R
	    end;
	R ->
	    R
    end;
field_recursion(Json, [{no_wildcard, Field}], Value, Query) ->
    NewQuery = lists:concat([Query, Field]),
    case get_field(Json, NewQuery) of
	R when is_list(R) ->
	    case lists:member(Value, lists:map(fun(X) when is_binary(X) -> binary:bin_to_list(X);
						  (X) -> X
					       end, R)) of
		true ->
		    Value;
		false ->
		    R
	    end;
	R ->
	    R
    end.

%% @doc
%% @hidden
%% Function: find_wildcard_fields/1
%% Purpose:  Search the query for fields ending with [*]
%% Returns:  A list containing the different parts of the query. Each element is
%%           tagged as {wildcard, X} or {no_wildcard, X}
%% @end
find_wildcard_fields(Query) ->
    WildCards = re:split(Query, "\\[\\*\\]", [{return, list}]),
    case lists:last(WildCards) of
	[] ->
	    NewWildCards = lists:filter(fun(X) -> X =/= [] end, WildCards),
	    lists:map(fun(X) -> {wildcard, X} end, NewWildCards);
	R ->
	    NewWildCards = lists:sublist(WildCards, length(WildCards)-1),
	    NewWildCards2 = lists:map(fun(X) -> {wildcard, X} end, NewWildCards),
	    NewWildCards2 ++ [{no_wildcard, R}]
    end.

%% @doc
%% @hidden
%% Function: format_output/2
%% @end
format_output(Value) when is_binary(Value) ->
    ?TO_STRING(Value);
format_output([]) ->
    [];
format_output(Value) when is_list(Value) ->
    %% erlang:display("0000"),
    try to_string(erlson:to_json(Value)) of
	NewValue ->
	    %% erlang:display("1***1"),
	    %% erlang:display(NewValue),
	    %% erlang:display("1***2"),
	    NewValue
    catch
	_:_ ->
	    try lists:map(fun(X) -> to_string(erlson:to_json(X)) end, Value) of
		NewValue ->
		    %% erlang:display("2***1"),
		    %% erlang:display(NewValue),
		    %% erlang:display("2***2"),
		    NewValue
	    catch
		_:_ ->
		    case lists:all(fun is_integer/1, Value) of
			true ->
			    %% erlang:display("3***1"),
			    %% erlang:display(Value),
			    %% erlang:display("3***2"),
			    Value;
			false ->
			    %% erlang:display("4***1"),
			    P = lists:map(fun(A) -> ?TO_STRING(A) end, Value),
			    %% erlang:display(P),
			    %% erlang:display("4***2"),
			    P
		    end
	    end
    end;
format_output(Value) ->
    Value.



%% @doc
%% @hidden
%% Function: get_field/1
%% Purpose: Get the value at a certain field
%% Returns: Return the string representation of the value of the specified 
%%          field, if it exists, otherwise returns 'false' value. If the desired
%%          value is a struct then no adaptation is performed.
%% @end
-spec get_field_internal(Json::string() | tuple(), Query::string()) -> string() | atom().
get_field_internal(Json, Attrs) ->
    try erlson:get_value(Attrs, Json) of
	"{}" ->
	    [];
	Result ->
	    Result
    catch
	error:_ -> undefined
    end.

%% @doc
%% @hidden
%% Function: get_field_max_index/2
%% Purpose: Makes a query for a field in order to find out the amount of items for that field.
%%          Does NOT handle wildcard queries
%% Returns: The length of the item list or 'false' if the field was not found
%% @end    
get_field_max_index(Json, Query) ->
    case get_field(Json, Query) of
	R when is_list(R) ->
	    length(R) - 1;
	R ->
	    R
    end.

%% @doc
%% @hidden
%% Function: index_recursion/4
%% Purpose: Handles recursion over indexes for one specific field
%% Returns: Either the found value or 'false'
%% @end
index_recursion(Json, [{wildcard, Field, 0 = N} | Rest], Value, Query) ->
    NewQuery = lists:concat([Query, Field]),
    NewIndexQuery = query_index_prep(NewQuery, N),
    field_recursion(Json, Rest, Value, NewIndexQuery);
index_recursion(Json, [{wildcard, Field, N} | Rest], Value, Query) ->
    NewQuery = lists:concat([Query, Field]),
    NewIndexQuery = query_index_prep(NewQuery, N),
    case field_recursion(Json, Rest, Value, NewIndexQuery) of
	Value ->
	    Value;
	_ ->
	    index_recursion(Json, [{wildcard, Field, N-1} | Rest], Value, Query)
    end.   

%% @doc
%% @hidden
%% Function: parse_attr/1
%% @end
parse_attr(Query) when is_atom(Query) ->
    Query;
parse_attr(Query) when is_list(Query) ->
    Fun = fun(X, Acc) ->
		  %% Produces a list such as ["attr1"] or ["attr2", "1]"]
		  case re:split(X, "\\[", [{return, list}]) of
		      [Attr] ->
			  %% The erlson library works on atoms
			  [list_to_atom(Attr)| Acc];
		      [Attr, IndexNoLeftBracket] ->
			  [Index, _] = re:split(IndexNoLeftBracket, "\\]", [{return, list}]),
			  %% The erlson library works on atoms and integers and the integers
			  %% cannot be 0, but the syntax specifies 0 as the first index,
			  %% so we add 1 to the index after conversion
			  [list_to_atom(Attr), (list_to_integer(Index)+1) | Acc] 
		  end
	  end,
    case lists:all(fun is_atom/1, Query) of
	true ->
	    Query;
	false ->
	    %% re:split/3 produces a list such as ["attr1", attr2[1], attr3]
	    try lists:foldr(Fun, [], re:split(Query, "\\.", [{return, list}])) of
		ParsedQuery ->
		    ParsedQuery
	    catch
		_:_ -> throw_incorrect_syntax(Query)
	    end
    end.
		    

%% @doc
%% @hidden
%% Function: parse_json/1
%% @end
parse_json(Json) when is_tuple(Json)->
    erlson:from_json_term(Json);
parse_json(Json) when is_list(Json)->
    erlson:from_json(Json).

%% @doc
%% @hidden
%% Function: parse_value/1
%% @end
parse_value([]) ->
    [];
parse_value({s, Value}) ->
     binary:list_to_bin(Value);
parse_value(Value) when is_tuple(Value)->
    %% erlang:display("poff0"),
    erlson:from_json_term(Value);
parse_value(Value) when is_list(Value) ->
    case {hd(Value), lists:last(Value)} of
	{${,$}} -> %% Check if Value is a proper json object
	    %% erlang:display("poff1"),
	    erlson:from_json(Value);
	{$[,$]} -> %% Check if Value is a json list
	    %% erlang:display("poff2"),
	    erlson:list_from_json_array(Value);
	{_ ,_ } -> %% Value is a list of values for an attribute
	    %% erlang:display("poff3***1"),
	    %% erlang:display(Value),	    
	    case lists:all(fun(X) -> erlson:is_json_string(X) end, Value) of
		true ->
		    %% erlang:display("poff3***2"),
		    lists:map(fun erlson:from_json/1, Value);
		false ->
		    %% erlang:display("poff3***3"),
		    lists:map(fun(X) -> ?JSON_VALUE(X) end, Value)
	    end		
    end;
parse_value(Value) ->
    %% erlang:display("poff4"),
    Value.

%% @doc
%% @hidden
%% Function: query_index_prep/2
%% Purpose: Encodes the index of a field for a json query
%% Returns: json query encoded as string()
%% @end
query_index_prep(Query, N) ->
    lists:concat([Query, "[", N, "]"]).

%% @doc
%% @hidden
%% Function: replace_field_internal/3
%% @end
replace_field_internal(Json, Attrs, Value) ->
    %% Check if the value exist, if it doesn't exist it shouldn't be replaced
    case erlson:get_value(Attrs, Json) of
	undefined ->
	    Json;
	_ ->
	    try erlson:store(Attrs, Value, Json) of
		NewJson ->
		    NewJson
	    catch
		_:_ ->
		    Json
	    end
    end.

%% @doc
%% @hidden
%% Function: rm_field_internal/2
%% @end
rm_field_internal(Json, Attrs) ->
    try erlson:remove(Attrs, Json) of
	NewJson ->
	    NewJson
    catch
	_:_ ->
	    Json
    end.

%% @doc
%% @hidden
%% Function: throw_incorrect_syntax/1
%% @end
throw_incorrect_syntax(Query) ->
    throw({incorrect_syntax, 
	   "The Query " ++ Query  
	   ++ " was badly formed, check your query again please."}).
