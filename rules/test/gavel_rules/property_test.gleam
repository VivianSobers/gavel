import gavel_rules/auction
import gavel_rules/support/gen
import gavel_rules/types.{
  AlreadyClosed, BidAccepted, Closed, Duplicate, Emit, Opened,
}
import gleam/list
import gleam/option.{None, Some}
import qcheck

pub fn run_sanity_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  let total_emitted =
    list.fold(history, 0, fn(acc, step) {
      let #(_before, _command, _now, outcome, _after) = step
      case outcome {
        Ok(Emit(events)) -> acc + list.length(events)
        _ -> acc
      }
    })
  let final_seq = case list.last(history) {
    Ok(#(_before, _command, _now, _outcome, after)) -> after.seq
    Error(_) -> 1
  }
  assert final_seq == 1 + total_emitted
}

pub fn high_bid_never_decreases_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  use #(before, _command, _now, _outcome, after) <- list.each(history)
  case before.high_bid, after.high_bid {
    Some(b1), Some(b2) -> {
      assert b2.amount >= b1.amount
      Nil
    }
    Some(_), None -> panic as "high bid disappeared"
    None, Some(b) -> {
      assert b.amount >= config.starting_price
      Nil
    }
    None, None -> Nil
  }
}

pub fn accepted_bids_meet_minimum_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  use #(before, _command, _now, outcome, _after) <- list.each(history)
  case outcome {
    Ok(Emit(events)) -> {
      use event <- list.each(events)
      case event {
        BidAccepted(b) -> {
          assert b.amount >= auction.minimum_next_bid(before)
          Nil
        }
        _ -> Nil
      }
    }
    _ -> Nil
  }
}

pub fn closed_auctions_reject_commands_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  use #(before, _command, _now, outcome, _after) <- list.each(history)
  case before.status {
    Closed ->
      case outcome {
        Ok(Duplicate(_)) -> Nil
        other -> {
          assert other == Error(AlreadyClosed)
          Nil
        }
      }
    _ -> Nil
  }
}

pub fn fold_matches_stepwise_evolve_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  let emitted_events =
    list.flat_map(history, fn(step) {
      let #(_before, _command, _now, outcome, _after) = step
      case outcome {
        Ok(Emit(events)) -> events
        _ -> []
      }
    })
  let all_events = [Opened(config), ..emitted_events]
  let final_state = case list.last(history) {
    Ok(#(_before, _command, _now, _outcome, after)) -> after
    Error(_) -> auction.evolve(auction.new(), Opened(config))
  }
  assert auction.fold(all_events) == final_state
}

pub fn end_time_never_decreases_property_test() {
  use #(config, steps) <- qcheck.given(gen.scenario())
  let history = gen.run(config, steps)
  use #(before, _command, _now, _outcome, after) <- list.each(history)
  assert after.ends_at >= before.ends_at
  assert after.ends_at >= config.ends_at
  Nil
}
