
let absolute_path path = 
  if Filename.is_relative path then 
    Filename.concat (Sys.getcwd ()) path 
  else 
    path 

(** [run_with_env cmd env] runs [cmd] in environment [env]. Returns [true] 
    if process exited normally and returned 0, [false] otherwise. *)
let run_with_env cmd args env = 
  let _pid = Unix.create_process_env cmd args env Unix.stdin Unix.stdout Unix.stderr in 
  let _wpid, status = Unix.wait () in 
  match status with 
  | Unix.WEXITED code -> code
  | _ -> -1

let add_to_current_env var value = 
  let env = Unix.environment () in 
  let new_var = Printf.sprintf "%s=%s" var value in 
  Array.append env [| new_var |] 

let generate_json_results xml_path = 
  if Sys.file_exists xml_path then 
    ()
  else
    ()

let root_object = 
  `Assoc [
    "version", `Int 2;
    "status", `String "fail";
    "message", `Null;
    "tests", `List []
  ]
  
let xml_file_suffix = "junit-results.xml"

let run_tests slug solution_dir output_dir = 
  let xml_file = Printf.sprintf "%s-%s" slug xml_file_suffix in 
  let abs_out_path = absolute_path output_dir in 
  let xml_path = Filename.concat abs_out_path xml_file in 
  let args = [| "make"; "-C"; solution_dir |] in 
  let env = add_to_current_env "OUNIT_OUTPUT_JUNIT_FILE" xml_path in 
  let run_code = run_with_env "make" args env in 
  false

let main slug solution_dir output_dir = 
  if run_tests slug solution_dir output_dir then 
    Printf.printf "***** OK!!!!"
  else 
    Printf.printf "***** ERROR!!!!!"

let () = 
  if Array.length Sys.argv < 4 then 
    failwith "Usage: runner <exercise-slug> <solution-dir> <output-dir>"
  else
    main Sys.argv.(1) Sys.argv.(2) Sys.argv.(3)
