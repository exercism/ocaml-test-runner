let expected_time = 40
let remaining_time already = expected_time - already
let preparation_time layers = 2 * layers
let total_time layers already = preparation_time layers + already
