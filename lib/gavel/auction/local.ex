defmodule Gavel.Auction.Local do
  @moduledoc """
  Local node interface for auction servers.
  """

  alias Gavel.Auction.Server

  @doc """
  Finds or starts an auction server and sends it a command with a 5-second timeout.
  """
  def command(auction_id, command) do
    with {:ok, pid} <- ensure_started(auction_id) do
      GenServer.call(pid, {:command, command}, 5_000)
    end
  catch
    :exit, {{:shutdown, :not_found}, _} ->
      {:error, :not_found}

    :exit, {:shutdown, :not_found} ->
      {:error, :not_found}

    # The server stopped before replying (it lost the fence or placement moved
    # it); the caller retries and gets a fresh server.
    :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :stale}

    # A crash or timeout may have happened after the commit. Retrying under the
    # same request id is safe and returns the original outcome.
    :exit, _reason ->
      {:error, :outcome_unknown}
  end

  @doc """
  Ensures that the auction server for the given auction ID is started locally.
  """
  @spec ensure_started(binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(auction_id) do
    case Registry.lookup(Gavel.Auction.Registry, auction_id) do
      # The Registry drops a stopped server's entry asynchronously, so a lookup
      # right after a stop can still return the dead pid.
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_server(auction_id)
        end

      [] ->
        start_server(auction_id)
    end
  end

  defp start_server(auction_id) do
    case DynamicSupervisor.start_child(
           Gavel.Auction.Supervisor,
           {Server, auction_id}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, {:shutdown, :not_found}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
