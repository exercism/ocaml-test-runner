(* leap - 1.5.1 *)
open OUnit2
open Leap

let ae exp got _test_ctxt = assert_equal exp got ~printer:string_of_bool

let tests = [
  "leap year" >::
  ae false (leap_year 1996);
  "not leap year" >::
  ae false (leap_year 1997);
]

let () =
  run_test_tt_main ("leap tests" >::: tests)
