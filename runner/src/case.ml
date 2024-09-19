type case = { name: string; task_id: int option; failmsg: string option }
type suite = { _tests: int; failures: int; errors: int; cases: case list }

let name_task_regexp = Str.regexp {|^\(.*\)\b @ task \([1-9]+\)$|}

let case_of_name raw_name failmsg =
  if Str.string_match name_task_regexp raw_name 0 then
    let group i = Str.matched_group i raw_name in
    let name = group 1
    and task_id = group 2 |> int_of_string_opt
    in { name; task_id; failmsg }
  else {name = raw_name; task_id = None; failmsg }
