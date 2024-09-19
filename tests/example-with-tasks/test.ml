open OUnit2
open Lucian_luscious_lasagna

let ae exp got _test_ctxt = assert_equal exp got ~printer:string_of_int

let tests =
  [ "expected time @ task 1" >:: ae 40 expected_time
  ; "remaining time @ task 2" >:: ae 10 @@ remaining_time 30
  ; "no more time @ task 2" >:: ae 0 @@ remaining_time 40
  ; "preparation time @ task 3" >:: ae 4 @@ preparation_time 2
  ; "total time @ task 4" >:: ae 26 @@ total_time 3 20
  ]
;;

let () = run_test_tt_main ("lasagna tests" >::: tests)
