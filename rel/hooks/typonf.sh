#!/usr/bin/env bash
script="/tmp/typonf.escript"
cat > $script <<EOF
%% -*- erlang -*-
main([File]) ->
  {ok, [In]} = file:consult(File),
  file:write_file(File, io_lib:format("~tp.~n", [replace(In)])).
replace({Key, {atom, <<>>, Default}}) -> {Key, Default};
replace({Key, {atom, Bin, _}}) -> replace({Key, {atom, Bin}});
replace({Key, {atom, Bin}}) -> {Key, binary_to_atom(Bin, utf8)};
replace({Key, {integer, <<>>, Default}}) -> {Key, Default};
replace({Key, {integer, Bin, _}}) -> replace({Key, {integer, Bin}});
replace({Key, {integer, Bin}}) -> {Key, list_to_integer(binary_to_list(Bin))};
replace({Key, {boolean, <<>>, Default}}) -> {Key, Default};
replace({Key, {boolean, Bin, _}}) -> replace({Key, {boolean, Bin}});
replace({Key, {boolean, <<"true">>}}) -> {Key, true};
replace({Key, {boolean, <<"True">>}}) -> {Key, true};
replace({Key, {boolean, <<"1">>}}) -> {Key, true};
replace({Key, {boolean, _}}) -> {Key, false};
replace({Key, Bin}) when is_binary(Bin) -> {Key, Bin};
replace({Key, Atom}) when is_atom(Atom) -> {Key, Atom};
replace({Key, List}) when is_list(List) -> {Key, replace(List)};
replace([]) -> [];
replace([H|T]) -> [replace(H)|replace(T)];
replace(Other) -> Other.
EOF
erts_dir=$(find /app -name "erts-*")
$erts_dir/bin/escript $script $DEST_SYS_CONFIG_PATH
