defmodule Gavel.Router do
  @moduledoc """
  Routes auction commands to the node that owns the auction.
  """

  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring

  @default_backoff_ms [50, 150, 400]
  @retryable [:stale, {:erpc, :noconnection}, {:erpc, :timeout}]

  @doc """
  Returns the cluster node currently owning the given auction ID.
  """
  def owner(auction_id) do
    Ring.owner(Membership.ring(), auction_id)
  end

  @doc """
  Dispatches a command to the owner node for the given auction ID.
  """
  def dispatch(auction_id, command) do
    backoffs = Application.get_env(:gavel, :router_backoff_ms, @default_backoff_ms)
    do_dispatch(auction_id, command, backoffs)
  end

  defp do_dispatch(auction_id, command, backoffs) do
    case rpc().call(
           owner(auction_id),
           Gavel.Auction.Local,
           :command,
           [auction_id, command],
           5_000
         ) do
      {:error, reason} when reason in @retryable -> retry(auction_id, command, backoffs)
      reply -> reply
    end
  end

  # Ownership may have moved (stale owner, lost or slow node): re-read the ring
  # after a backoff, and give up once the backoffs are used.
  defp retry(_auction_id, _command, []), do: {:error, :unavailable}

  defp retry(auction_id, command, [sleep_ms | rest]) do
    Process.sleep(sleep_ms)
    do_dispatch(auction_id, command, rest)
  end

  defp rpc do
    Application.get_env(:gavel, :rpc, Gavel.Cluster.Rpc)
  end
end
