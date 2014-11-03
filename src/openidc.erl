%% @author Alberto Blazquez <albl1900@student.uu.se>
%% [www.csproj13.student.it.uu.se]
%% @version 1.0
%% @copyright [Copyright information]

%% @doc == openidc ==
%% Authentication/Authorization module based upon the OpenID Connect protocol
%% It relies heavily on the Google Sign in API (the Identity Provider)
%%
%% @end

-module(openidc).
-export([init/1,
         auth_request/1,
         authenticate/2,
         authorize/2,
         generate_idp_token/2,
         generate_own_token/1,
         store_own_token/1,
         is_admin/1,
         process_auth_request/2,
         process_auth_redirect/2,
         process_renew_token/2,
         process_renew_both_tokens/2
        ]).

-include("field_restrictions.hrl").

% TODO Grab these settings from a config file
-define(APIKEY, "AIzaSyCyC23vutanlgth_1INqQdZsv6AgZRiknY").
-define(CLIENT_ID, "995342763478-fh8bd2u58n1tl98nmec5jrd76dkbeksq.apps.googleusercontent.com").
-define(CLIENT_SECRET, "fVpjWngIEny9VTf3ZPZr8Sh6").
-define(REDIRECT_URL, "http://localhost:8000/users/_openid").

-define(FRONTEND_ID, "107908217220817548513").
-define(PUB_SUB_ID,  "<< add here ... >>").
-define(POLLING_ID,  "<< add here ... >>").

-define(STATUS_AUTHENTICATION_FAIL, 498).
-define(STATUS_AUTHORISATION_FAIL, 401).
-define(STATUS_TOO_MANY_REQUESTS, 429).

-define(REQUESTS_DAY_LIMIT, 70000).


% %% @doc
% %% Function: init/1
% %% Purpose: init function used to fetch path information from webmachine dispatcher.
% %% Returns: {ok, undefined}
% %% @end
-spec init([]) -> {ok, undefined}.
init([]) ->
    {ok, undefined}.


-spec process_auth_request(ReqData::tuple(), State::string()) -> string().
process_auth_request(ReqData, State) ->
    plus_srv:start_link(?APIKEY, ?CLIENT_ID, ?CLIENT_SECRET, ?REDIRECT_URL),
    plus_srv:set_api("https://www.googleapis.com/discovery/v1/apis/plus/v1/rest"),
    plus_srv:gen_token_url("https://www.googleapis.com/auth/plus.me").


-spec process_auth_redirect(ReqData::tuple(), State::string()) -> tuple().
process_auth_redirect(ReqData, State) ->
    case {wrq:get_qs_value("code", ReqData), wrq:get_qs_value("state", ReqData)} of
        {undefined, _} -> {error, "State missing"};
        {_, undefined} -> {error, "Code missing"};

        {Code, AuthState} when Code =/= "", AuthState =/= "" ->
            case generate_idp_token(Code, AuthState) of
                {true, Res}    -> {ok, Res};
                {false, Error} -> {error, Error}
            end;

        _ -> {error, "Unsupported field(s) on the auth request"}
    end.


-spec process_renew_token(ReqData::tuple(), State::string()) -> tuple().
process_renew_token(ReqData, State) ->
    RToken = wrq:get_req_header("Refresh-Token", ReqData),
    UserID = wrq:get_req_header("Username", ReqData),

    case {RToken, UserID} of
        {undefined, _} -> {error, "Failed operation: Missing refresh_token"};
        {_, undefined} -> {error, "Failed operation: Missing username"};
        _ ->
            case is_own_token(RToken) of
                false                ->
                    erlang:display("idp"),
                    renew_idp_token(UserID, RToken);
                {true, OldTokenJSON} ->
                    erlang:display("own"),
                    renew_own_token(UserID, RToken, OldTokenJSON)
            end
    end.


-spec process_renew_both_tokens(ReqData::tuple(), State::string()) -> tuple().
process_renew_both_tokens(ReqData, State) ->
    AccToken = wrq:get_req_header("Access-Token", ReqData),
    RefToken = wrq:get_req_header("Refresh-Token", ReqData),

    case authenticate("Access-Token", ReqData) of
        {error, ErrorMsg} -> {error, ErrorMsg};
        {ok, UserID} ->
            Res1 = replace_token(UserID, "access_token", list_to_binary(AccToken)),
            Res2 = replace_token(UserID, "refresh_token", list_to_binary(RefToken)),
            case {Res1, Res2} of
                {{error, Err1}, _} -> {error, Err1};
                {_, {error, Err2}} -> {error, Err2};
                {{ok, _}, {ok, _}} -> {ok, UserID}
            end
    end.


-spec renew_idp_token(UserID::string(), RefToken::string()) -> tuple().
renew_idp_token(UserID, RefToken) ->
    Client = "client_id=" ++ ?CLIENT_ID,
    Secret = "&client_secret=" ++ ?CLIENT_SECRET,
    RToken = "&refresh_token=" ++ RefToken,
    G_Type = "&grant_type=refresh_token",

    URL    = "https://accounts.google.com/o/oauth2/token",
    Header = "application/x-www-form-urlencoded",
    Body   = Client ++ Secret ++ RToken ++ G_Type,
    erlang:display(URL),
    erlang:display(Body),
    Request = httpc:request(post, {URL, [], Header, Body}, [], []),
    case plus_srv:get_url(Request) of
        {error, _} ->
            erlang:display("RT not valid"),
            {error, "Refresh Token not valid"};
        {ok, JSON} ->
            case proplists:get_value(<<"access_token">>, JSON) of
                undefined ->
                    erlang:display("Token not valid"),
                    {error, "Token not valid"};
                AccToken  ->
                    erlang:display("New Acc Token"),
                    erlang:display(AccToken),
                    case replace_token(UserID, "access_token", AccToken) of
                        {error, Error} -> erlang:display("not replace"),{error, Error};
                        {ok, _}        -> erlang:display("replace"),{ok, binary_to_list(AccToken)}
                    end
            end
    end.


-spec renew_own_token(UserID::string(), RefToken::string(), OldTokenJSON::tuple()) -> tuple().
renew_own_token(UserID, RefToken, OldTokenJSON) ->
    case lib_json:get_field(OldTokenJSON, "access_token") of
        undefined   -> {error, "Access token not found on database"};
        OldAccToken ->
            % Create new token based on the given RefToken
            TokenJSON = generate_own_token(list_to_binary(UserID), list_to_binary(RefToken)),

            case users:get_user_by_name(UserID) of
                {error, Err}   -> {error, Err};
                {ok, UserJSON} ->
                    AccToken = lib_json:get_field(TokenJSON, "access_token"),

                    UserJSON2  = lib_json:replace_field(UserJSON, "access_token", AccToken),
                    UserUpdate = lib_json:set_attr(doc, UserJSON2),
                    api_help:update_doc(?INDEX, "user", UserID, UserUpdate),

                    Res = erlastic_search:delete_doc(?INDEX, "token", OldAccToken),
                    store_own_token(TokenJSON)
            end
    end.


-spec is_own_token(Token::string()) -> boolean().
is_own_token(Token) ->
    Query = "refresh_token:" ++ Token,
    case erlastic_search:search_limit(?INDEX, "token", Query, 1) of
        {error, _} -> false;
        {ok, JSON} ->
            Source    = lib_json:get_field(JSON, "hits.hits"),
            TokenJSON = lib_json:get_field(Source, "_source"),
            {true, TokenJSON}
    end.


-spec generate_idp_token(Code::string(), AuthState::string()) -> string().
generate_idp_token(Code, AuthState) ->
    {AccToken, RefToken} = exchange_token(Code, AuthState),

    case AccToken of
        undefined -> {false, "Not possible to authenticate. Missing Access Token"};
        _ ->
            case fetch_user_info() of
                {error, _} -> {false, "Not possible to authenticate. Unreachable user info"};
                {ok, UserData} ->
                    Username = binary_to_list(proplists:get_value(<<"id">>, UserData)),
                    Status = case users:user_is_new(Username) of
                        true  -> users:store_user(UserData, AccToken, RefToken);
                        false ->
                            replace_token(Username, "access_token", AccToken),
                            replace_token(Username, "refresh_token", RefToken)
                    end,

                    case Status of
                        {error, Msg} -> {error, Msg};
                        {ok, _} ->
                            Struct = {struct, [
                                {access_token, AccToken},
                                {refresh_token, RefToken}
                            ]},
                            Res = mochijson2:encode(Struct),
                            {true, Res}
                    end
            end
    end.


-spec generate_own_token(Username::string()) -> tuple().
generate_own_token(Username) ->
    RT = base64:encode(crypto:strong_rand_bytes(48)),
    RefToken = list_to_binary(re:replace(RT, "/|\\+", "0", [global, {return, list}])),
    generate_own_token(Username, RefToken).


-spec generate_own_token(Username::string(), RefToken::string()) -> tuple().
generate_own_token(Username, RefToken) ->
    AT = base64:encode(crypto:strong_rand_bytes(64)),
    AccToken = list_to_binary(re:replace(AT, "/|\\+", "0", [global, {return, list}])),

    TokenJSON = mochijson2:encode({struct, [
        {access_token, AccToken},
        {expires_in, 3600},
        {issued_at, api_help:now_to_seconds()},
        {refresh_token, RefToken},
        {user_id, Username}
    ]}).


-spec store_own_token(TokenJSON::tuple()) -> tuple().
store_own_token(TokenJSON) ->
    AccToken = lib_json:get_field(TokenJSON, "access_token"),
    case erlastic_search:index_doc_with_id(?INDEX, "token", AccToken, TokenJSON) of
        {error, _} -> {error, "Not possible to store the generated token"};
        {ok, _}    -> {ok, binary_to_list(AccToken)}
    end.


-spec auth_request(ReqData::tuple()) -> tuple().
auth_request(ReqData) ->
    case authenticate("Access-Token", ReqData) of
        {error, Error} -> {error, ?STATUS_AUTHENTICATION_FAIL, "{\"error\": \"" ++ Error ++ "\"}"};
        {ok, TokenOwner}   -> authorize(ReqData, TokenOwner)
    end.


-spec authenticate(TokenName::string(), ReqData::tuple()) -> tuple().
authenticate(TokenName, ReqData) ->
    ErrorMsg = "Not possible to perform the request. Missing " ++ TokenName,
    case wrq:get_req_header(TokenName, ReqData) of
        undefined -> {error, ErrorMsg};
        ""        -> {error, ErrorMsg};
        TokenVal  -> check_valid_token(TokenName, list_to_binary(TokenVal))
    end.


-spec authorize(ReqData::tuple(), TokenOwner::string()) -> tuple().
authorize(ReqData, TokenOwner) ->
    {Method, Resource, UserRequested, Private} = api_help:get_info_request(ReqData),

    case is_admin(TokenOwner) of
        true -> {ok, TokenOwner};
        false ->
            ValidAccess = case UserRequested of
                undefined -> authorization_rules_collection(Method, Resource);
                _         -> authorization_rules_individual(Method, Resource, UserRequested, Private, TokenOwner)
            end,

            case ValidAccess of
                false ->
                    Error1 = "{\"error\": \"User not authorized. Permission denied\"}",
                    {error, ?STATUS_AUTHORISATION_FAIL, Error1};

                true  ->
                    case check_requests_day(TokenOwner) of
                        false ->
                            Error2 = "{\"error\": \"User has reached the maximum limit of requests/day. Permission denied\"}",
                            {error, ?STATUS_TOO_MANY_REQUESTS, Error2};
                        true -> {ok, TokenOwner}
                    end
            end
    end.


-spec check_requests_day(Username::string()) -> boolean().
check_requests_day(Username) ->
    TableName = "requests",
    UserID = list_to_binary(Username),

    case erlastic_search:get_doc(?INDEX, TableName, UserID) of
        {error, _} -> % Insert a new record
            JSON = lib_json:set_attrs([
                {user_id, UserID},
                {number, 0},
                {"_ttl.enabled", true},
                {"_ttl.default", "1d"}
            ]),
            erlang:display(JSON),
            erlastic_search:index_doc_with_id(?INDEX, TableName, UserID, JSON),
            true;

        {ok, Doc} -> % Check if current number is over limit
            JSON   = lib_json:get_field(Doc, "_source"),
            Number = lib_json:get_field(JSON, "number"),

            erlang:display({Number, ?REQUESTS_DAY_LIMIT, Number >= ?REQUESTS_DAY_LIMIT}),
            case Number >= ?REQUESTS_DAY_LIMIT of
                true  -> false;
                false ->
                    JSON2 = lib_json:replace_field(JSON, "number", Number+1),
                    Update = lib_json:set_attr(doc, JSON2),
                    erlang:display(Update),
                    api_help:update_doc(?INDEX, TableName, UserID, Update),
                    true
            end
    end.


-spec authorization_rules_individual(Method::atom(), Resource::string(),
    UserRequested::string(), Private::boolean(), TokenOwner::string()) -> boolean().
authorization_rules_individual(Method, Resource, UserRequested, Private, TokenOwner) ->
    erlang:display(UserRequested),
    erlang:display(TokenOwner),

    Res = case {UserRequested == TokenOwner, Private} of
        {true, _}      -> %true;                   % Exception 1: Can MAKE anything with his/her own data
               erlang:display("exp.1"), true;
        {false, true}  -> %false;                  % Exception 2: Can NOT MAKE anything to private resources
               erlang:display("exp.2"), false;

        {false, false} ->
            case {Method, Resource} of
                {'GET',    "users"} -> erlang:display("exp.3"), true;      % Exception 3: Can ONLY GET public User/Streams/VS
                {'GET',  "streams"} -> erlang:display("exp.3"), true;
                {'GET', "vstreams"} -> erlang:display("exp.3"), true;

                {'PUT', "rank"} -> %true;          % Exception 4: Can ONLY PUT other's ranking of a stream
                    erlang:display("exp.4"), true;

                {_, "_search"} ->
                    erlang:display("search rule"), true;

                _ -> erlang:display("rule"), false                        % Rule: Anything else is forbidden
            end;

        _ -> false                                %       Anything else is forbidden
    end,

    erlang:display({"Granted Access:", Res}),
    Res.


-spec authorization_rules_collection(Method::atom(), Resource::string()) -> boolean().
authorization_rules_collection(Method, Resource) ->
    % Exception 5: Only fetch a collection or create a new User, Stream or Virtual Stream is allowed
    % This rule is checked in cases when a GET /users or POST to /streams, without a specific user id, is requested
    ValidResourceGet = lists:member(Resource, ["users", "suggest", "resources"]),
    ValidGET = ValidResourceGet and (Method == 'GET'),

    ValidResourcePost = lists:member(Resource, ["users", "streams", "vstreams", "triggers", "resources"]),
    ValidPOST = ValidResourcePost and (Method == 'POST'),

    Res = ValidGET or ValidPOST,
    erlang:display("Rule 5"),
    erlang:display({"Granted Access:", Res}),
    Res.


-spec check_valid_token(TokenName::string(), TokenValue::string()) -> tuple().
check_valid_token(TokenName, TokenValue) ->
    case verify_idp_token(TokenValue) of
        {error, _} ->
            case verify_own_token(TokenValue) of
                {error, Error}     -> {error, Error};
                {ok, false, _}     -> {error, "Token not valid"};
                {ok, true, UserID} -> {ok, UserID}
            end;

        {ok, GoogleJSON} ->
            case analyse_token_response(GoogleJSON) of
                {error, Error}     -> {error, Error};
                {ok, false, _}     -> {error, "Token not valid"};
                {ok, true, UserID} ->
                    replace_token(UserID, "Access-Token",  TokenValue),
                    {ok, UserID}
            end
    end.


-spec verify_idp_token(Token::string()) -> tuple().
verify_idp_token(Token) ->
    AuthURL = "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=" ++ binary_to_list(Token),
    case plus_srv:get_url(httpc:request(get,{AuthURL,[]},[],[])) of
        {ok, Json} -> {ok, Json};
        {error, _} -> {error, "Token not valid or already expired"}
    end.


-spec verify_own_token(AccToken::string()) -> boolean().
verify_own_token(AccToken) ->
    case look_up_token(AccToken) of
        {error, Error} -> {error, Error};
        {ok, JSON} ->
            UserID = binary_to_list(lib_json:get_field(JSON, "_source.user_id")),

            CurrentTS = api_help:now_to_seconds(),
            IssuedAt  = lib_json:get_field(JSON, "_source.issued_at"),
            ExpiresIn = lib_json:get_field(JSON, "_source.expires_in"),  % 3600 seconds usually

            Valid = (CurrentTS < (IssuedAt + ExpiresIn)),
            {ok, Valid, UserID}
    end.


-spec analyse_token_response(JSON::tuple()) -> tuple().
analyse_token_response(JSON) ->
    case proplists:get_value(<<"error">>, JSON) of
        undefined ->
            GoogleUsername = binary_to_list(proplists:get_value(<<"user_id">>, JSON)),
            case binary_to_list(proplists:get_value(<<"audience">>, JSON)) of
                undefined -> {error, "Token not valid. Audience field not found"};
                Audience  ->
                    Valid = (Audience == ?CLIENT_ID),
                    {ok, Valid, GoogleUsername}
            end;
        _ -> {error, "Error verifying the token with Identity Provider"}
    end.


-spec look_up_token(AccToken::string()) -> tuple().
look_up_token(AccToken) ->
    case erlastic_search:get_doc(?INDEX, "token", AccToken) of
        {error, _} -> {error, "Token not found on the database"};
        {ok, List} -> {ok, List}
    end.


-spec replace_token(Username::string(), TokenName::string(), TokenValue::string()) -> tuple().
replace_token(Username, "Access-Token",  TokenValue) -> replace_token(Username, "access_token",  TokenValue);
replace_token(Username, "Refresh-Token", TokenValue) -> replace_token(Username, "refresh_token", TokenValue);
replace_token(Username, TokenName, TokenValue) ->
    case users:get_user_by_name(Username) of
        {error, _} -> {error, "User not found on database"};
        {ok, JSON} ->
            OldToken = lib_json:get_field(JSON, TokenName),
            case OldToken == TokenValue of   % Optimization, to not update if it is not needed
                true  -> {ok, JSON};
                false ->
                    UserJSON = lib_json:replace_field(JSON, TokenName, TokenValue),
                    Update   = lib_json:set_attr(doc, UserJSON),
                    case api_help:update_doc(?INDEX, "user", Username, Update) of
                        {ok,    _} -> {ok, UserJSON};
                        {error, _} -> {error, "Not possible to update the user"}
                    end
            end
    end.


-spec is_admin(Username::string()) -> boolean().
is_admin(Username) ->
    (Username == ?FRONTEND_ID) or (Username == ?PUB_SUB_ID) or (Username == ?POLLING_ID).


-spec fetch_user_info() -> tuple().
fetch_user_info() ->
    plus_srv:call_method("plus.people.get", [{"userId", "me"}], []).


-spec exchange_token(Code::string(), AuthState::string()) -> string().
exchange_token(Code, AuthState) ->
    Token = plus_srv:exchange_token(Code, AuthState),
    AccToken = proplists:get_value(<<"access_token">>, Token),
    RefToken = proplists:get_value(<<"refresh_token">>, Token),
    {AccToken, RefToken}.
