open Ezxmlm

let version = 3
let version_json = `Int version

let absolute_path path = 
  if Filename.is_relative path then 
    Filename.concat (Sys.getcwd ()) path 
  else 
    path 

(** [run_with_env cmd env] runs [cmd] in environment [env]. Returns [true] 
    if process exited normally and returned 0, [false] otherwise. *)
let run_with_env cmd args env = 
  let stdout, stdin, stderr = Unix.open_process_args_full cmd args env in 
  let out = In_channel.input_all stdout in 
  let err = In_channel.input_all stderr in 
  let status = Unix.close_process_full (stdout, stdin, stderr) in 
  match status with 
  | Unix.WEXITED code -> (code, out, err)
  | _ -> (-1, out, err)


let add_to_current_env var value = 
  let env = Unix.environment () in 
  let new_var = Printf.sprintf "%s=%s" var value in 
  Array.append env [| new_var |] 

type case = { name: string; task_id: int option; failmsg: string option } 
type suite = { _tests: int; failures: int; errors: int; cases: case list }

let check_case_failure case =
  match members_with_attr "failure" case with 
  | [] -> None
  | [ attrs, _nodes ] -> Some (get_attr "message" attrs) 
  | _ -> failwith "This should never happen"

let read_case case_with_attrs = 
  let attrs = fst case_with_attrs in
  let name = get_attr "name" attrs
  and failmsg = check_case_failure (snd case_with_attrs) in
  { name; task_id = None; failmsg }

let read_xml_from_channel ch = 
  let (_, xml) = from_channel ch in 
  let suites = member "testsuites" xml |> members_with_attr "testsuite" in
  let first_suite = List.hd suites in 
  let suite_attrs = fst first_suite in
  let n_tests = get_attr "tests" suite_attrs |> int_of_string in
  let n_failures = get_attr "failures" suite_attrs |> int_of_string in 
  let n_errors = get_attr "errors" suite_attrs |> int_of_string in 
  { 
    _tests = n_tests; 
    failures = n_failures; 
    errors = n_errors;
    cases = members_with_attr "testcase" (snd first_suite) 
            |> List.map read_case 
  }
   
let read_xml fname = 
  In_channel.with_open_text fname read_xml_from_channel

let task_id_json (task_id: int option): [> `Int of int | `Null] =
  task_id |> Option.map (fun id -> `Int id) |> Option.value ~default:`Null

let build_case_json case status msg = 
  `Assoc [
    "name", `String case.name;
    "status", `String status;
    "message", msg;
    "output", `Null;
    "test_code", `Null;
    "task_id", task_id_json case.task_id
  ]

let case_json case = 
  match case.failmsg with 
  | None -> build_case_json case "pass" `Null
  | Some m -> build_case_json case "fail" (`String m)
  
let root_object status msg cases_json = 
  `Assoc [
    "version", version_json;
    "status", `String status;
    "message", msg;
    "tests", `List cases_json
  ]

let error_root_object msg = 
  `Assoc [
    "version", version_json;
    "status", `String "error";
    "message", `String msg;
    "tests", `Null
  ] 
  
let sort_cases cases = 
  List.sort (fun c1 c2 -> String.compare c1.name c2.name) cases 

let json_from_suite_results suite = 
  match suite.failures, suite.errors with 
  | 0, 0 -> root_object "pass" `Null (List.map case_json (sort_cases suite.cases))
  | _, 0 -> root_object "fail" `Null (List.map case_json (sort_cases suite.cases))
  | _, _ -> root_object "error" (`String "unknown compiler error") []

let generate_json_results xml_path err = 
  if Sys.file_exists xml_path then 
    json_from_suite_results @@ read_xml xml_path
  else
    error_root_object err 

let xml_file_suffix = "junit-results.xml"

let sanitize_error_output err = 
  String.trim err 

let run_tests slug solution_dir output_dir = 
  let xml_file = Printf.sprintf "%s-%s" slug xml_file_suffix in 
  let abs_out_path = absolute_path output_dir in 
  let xml_path = Filename.concat abs_out_path xml_file in 
  let args = [| "make"; "-C"; solution_dir |] in 
  let env = add_to_current_env "OUNIT_OUTPUT_JUNIT_FILE" xml_path in 
  let _code, _out, err = run_with_env "make" args env in 
  let sanitized_err = sanitize_error_output err in 
  generate_json_results xml_path sanitized_err

let main slug solution_dir output_dir = 
  let abs_out_path = absolute_path output_dir in 
  let out_file = Filename.concat abs_out_path "results.json" in
  let json_object = run_tests slug solution_dir output_dir in 
  Out_channel.with_open_text out_file @@ fun ch ->
    Yojson.pretty_to_channel ch json_object 

let () = 
  if Array.length Sys.argv < 4 then 
    failwith "Usage: runner <exercise-slug> <solution-dir> <output-dir>"
  else
    main Sys.argv.(1) Sys.argv.(2) Sys.argv.(3)
