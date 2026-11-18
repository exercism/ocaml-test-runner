(* The fast path compiles a solution with a single ocamlopt call and runs the
   test executable directly, without make or dune.

   The usual path runs `make`, which runs `dune clean` and `dune runtest`.
   Dune loads its 34 MB binary, reads the META file of every installed
   library, and then compiles each module twice (bytecode with ocamlc and
   native code with ocamlopt) after running ocamldep on it. Every one of
   those programs is a separate 18-22 MB binary. A single ocamlopt call reads
   about half as much from disk, which matters most for the first run on a
   machine, when none of these files are in the page cache.

   The image build (bin/record-fast-path.sh) records the ocamlopt arguments
   dune uses for each library set found in the track's exercises. The fast
   path only accepts a solution if its dune, dune-project and Makefile match
   the track's standard files. If anything is unusual, or if compiling or
   running the tests does not produce a JUnit report, the runner falls back
   to the usual path, so error messages stay exactly as before. *)

let args_dir = "/opt/test-runner/fast-path"

let ocamlopt = "/home/opam/.opam/5.5/bin/ocamlopt.opt"

let read_file path = In_channel.with_open_bin path In_channel.input_all

(* Collapses every run of whitespace into one space and removes the spaces
   next to brackets, so files that only differ in layout compare equal. *)
let normalise s =
  let s = Str.global_replace (Str.regexp "[ \t\r\n]+") " " s |> String.trim in
  let s = Str.global_replace (Str.regexp " *( *") "(" s in
  Str.global_replace (Str.regexp " *) *") ")" s

let makefile_is_standard dir =
  let makefile = Filename.concat dir "Makefile" in
  Sys.file_exists makefile
  && Str.global_replace (Str.regexp "[ \t\r\n]+") " " (read_file makefile)
     |> String.trim
     = "default: clean test test: dune runtest clean: dune clean .PHONY: clean"

(* Dune lang 1.1 keeps module names as they are (later versions wrap
   executables in a Dune__exe module). The recorded flags match it. *)
let dune_project_is_standard dir =
  let path = Filename.concat dir "dune-project" in
  Sys.file_exists path
  && Str.string_match
       (Str.regexp {|^(lang dune 1\.1)\((version [^()]*)\)?$|})
       (normalise (read_file path)) 0

let dune_prefix = "(executable(name test)(libraries "

let dune_suffix =
  "))(alias(name runtest)(deps(:x test.exe))(action(run %{x})))\
   (alias(name buildtest)(deps(:x test.exe)))\
   (env(dev(flags(:standard -warn-error -A))))"

(* Returns the libraries listed in the dune file if it is the track's standard
   one, which builds test.exe from every module in the folder and runs it. *)
let standard_dune_libraries dir =
  let path = Filename.concat dir "dune" in
  if not (Sys.file_exists path) then None
  else
    let re =
      Str.regexp
        ("^" ^ Str.quote dune_prefix ^ {|\([a-z0-9_ ]+\)|} ^ Str.quote dune_suffix ^ "$")
    in
    let dune = normalise (read_file path) in
    if Str.string_match re dune 0 then Some (Str.matched_group 1 dune) else None

let recorded_args libraries =
  let path =
    Filename.concat args_dir (String.concat "-" (String.split_on_char ' ' libraries))
  in
  if Sys.file_exists path then
    Some (read_file path |> String.split_on_char '\n' |> List.filter (( <> ) ""))
  else None

let valid_module_name = Str.regexp {|^[A-Za-z][A-Za-z0-9_']*$|}

(* Files dune would ignore here, or that do not change the build. *)
let ignored_file name =
  name.[0] = '.'
  || List.mem name [ "dune"; "dune-project"; "Makefile"; "_tags" ]
  || List.mem (Filename.extension name) [ ".md"; ".json"; ".xml"; ".txt"; ".log" ]

(* Returns the .ml and .mli files, or None if the folder holds anything
   else dune might build (subfolders, lexers, parsers, C stubs...). *)
let source_files dir =
  let entries = Sys.readdir dir |> Array.to_list |> List.sort String.compare in
  let classify name =
    let path = Filename.concat dir name in
    if Sys.is_directory path then
      if name.[0] = '.' || name.[0] = '_' then `Ignore else `Unknown
    else
      match Filename.extension name with
      | ".ml" | ".mli" ->
          if Str.string_match valid_module_name (Filename.remove_extension name) 0
          then `Source
          else `Unknown
      | _ -> if ignored_file name then `Ignore else `Unknown
  in
  let classified = List.map (fun name -> (name, classify name)) entries in
  if List.exists (fun (_, c) -> c = `Unknown) classified then None
  else
    let sources = List.filter_map (fun (n, c) -> if c = `Source then Some n else None) classified in
    let module_names ext =
      List.filter (fun n -> Filename.extension n = ext) sources
      |> List.map (fun n -> String.capitalize_ascii (Filename.remove_extension n))
    in
    let unique names = List.length (List.sort_uniq String.compare names) = List.length names in
    if List.mem "test.ml" sources && unique (module_names ".ml") && unique (module_names ".mli")
    then Some sources
    else None

(* Runs a program in [cwd] with its output discarded, and returns its output
   on stdout if it exits with 0. *)
let run ?(env = Unix.environment ()) ~cwd prog args =
  let previous = Sys.getcwd () in
  Sys.chdir cwd;
  Fun.protect ~finally:(fun () -> Sys.chdir previous) @@ fun () ->
  let null = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
  let out_read, out_write = Unix.pipe ~cloexec:true () in
  let pid = Unix.create_process_env prog (Array.of_list (prog :: args)) env null out_write null in
  Unix.close out_write;
  Unix.close null;
  let output = In_channel.input_all (Unix.in_channel_of_descr out_read) in
  Unix.close out_read;
  match Unix.waitpid [] pid with
  | _, Unix.WEXITED 0 -> Some output
  | _ -> None

let copy_file src dst =
  Out_channel.with_open_bin dst (fun oc -> Out_channel.output_string oc (read_file src))

(* Returns true if it wrote the JUnit report to [xml_path]. *)
let try_run_tests solution_dir xml_path =
  match
    if makefile_is_standard solution_dir && dune_project_is_standard solution_dir then
      standard_dune_libraries solution_dir
    else None
  with
  | None -> false
  | Some libraries -> (
      match (recorded_args libraries, source_files solution_dir) with
      | Some args, Some sources -> (
          (* Build where dune would, in the solution's _build folder. The
             solution folder is writable and allows running programs, which
             /tmp may not (the repo's tests mount /tmp with noexec). *)
          let build_dir = Filename.concat (Filename.concat solution_dir "_build") "fast-path" in
          List.iter
            (fun d -> if not (Sys.file_exists d) then Sys.mkdir d 0o755)
            [ Filename.dirname build_dir; build_dir ];
          List.iter
            (fun f -> copy_file (Filename.concat solution_dir f) (Filename.concat build_dir f))
            sources;
          if Sys.file_exists xml_path then Sys.remove xml_path;
          (* `ocamlopt -depend -sort` orders the files so that each module
             comes after the modules it uses, as dune's ocamldep step does. *)
          match run ~cwd:build_dir ocamlopt ([ "-depend"; "-sort" ] @ sources) with
          | None -> false
          | Some sorted -> (
              let sorted = String.split_on_char ' ' (String.trim sorted) in
              match run ~cwd:build_dir ocamlopt (args @ sorted) with
              | None -> false
              | Some _ ->
                  (* OUnit's default runner runs the tests in two worker
                     processes, and waits 0.1 s for each worker to exit at the
                     end. The sequential runner runs them in this process.
                     If a test crashes the process, no report gets written
                     and the usual path runs the tests the old way. *)
                  let env =
                    Array.append (Unix.environment ())
                      [| "OUNIT_OUTPUT_JUNIT_FILE=" ^ xml_path; "OUNIT_RUNNER=sequential" |]
                  in
                  ignore (run ~env ~cwd:build_dir (Filename.concat build_dir "test.exe") []);
                  Sys.file_exists xml_path))
      | _ -> false)

(* Any unexpected error sends the solution down the usual path. *)
let run_tests solution_dir xml_path =
  try try_run_tests solution_dir xml_path with _ -> false
