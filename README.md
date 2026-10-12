# gavel

Status: early

gavel is a clustered realtime auction service. Each open auction is one Erlang process. Bidders watch a live bid ladder in the browser and bid against each other and against load-generator bots. Any app node can be killed at any moment: its auctions restart on the surviving nodes, rebuilt from the bid log, and no accepted bid is lost, duplicated or reordered.

## Guarantees

1. A bid is acknowledged as accepted only after its event is committed to Postgres.
2. Per auction, the log is a single totally ordered sequence `seq = 1..n` with no gaps.
3. Each client request id appears at most once in the log; a retried request returns the original outcome.
4. Replaying an auction's log through the rules core accepts every event (the log is a valid history under the rules).
5. Every auction whose end time has passed gets exactly one `Closed` event, it is the last event, and its winner is the highest bid if the reserve is met.

Durability and ordering come from the Postgres fence. The BEAM side provides availability, low-latency serialized validation, timers, and fan-out.

## Requirements

- Docker (with Docker Compose)
- make

## Quickstart

```sh
make image
make check
```
