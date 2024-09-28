open OUnit2
open Case

let string_of_case case =
  let pattern = Printf.sprintf "{ name = '%s'; task_id = %s; failmsg = '%s' }"
  and task_id_repr = case.task_id |> Option.map string_of_int |> Option.value ~default:"None"
  and failmsg_repr = case.failmsg |> Option.value ~default:"None"
  in pattern case.name task_id_repr failmsg_repr

let ae exp got _test_ctxt = assert_equal exp got ~printer:string_of_case

let tests = [
    "Nominal example" >::
      ae { name = "Test"; task_id = Some 1; failmsg = Some "fail" } @@ case_of_name "Test @ task 1" (Some "fail") 
    ; "Without task" >::
      ae { name = "Test"; task_id = None; failmsg = None } @@ case_of_name "Test" None
    ; "With task (multiple digits id)" >::
      ae { name = "Test"; task_id = Some 210; failmsg = None } @@ case_of_name "Test @ task 210" None
    ; "@ task without id" >::
      ae { name = "Test @ task"; task_id = None; failmsg = None } @@ case_of_name "Test @ task" None
    ; "@ task with id 0" >::
      ae { name = "Test @ task 0"; task_id = None; failmsg = None } @@ case_of_name "Test @ task 0" None
    ; "@ task with non integer id" >::
      ae { name = "Test @ task foo"; task_id = None; failmsg = None } @@ case_of_name "Test @ task foo" None
    ; "@ task with no test name" >::
      ae { name = " @ task 1"; task_id = None; failmsg = None } @@ case_of_name " @ task 1" None
  ]
;;

let () = run_test_tt_main ("runner tests" >::: tests)
