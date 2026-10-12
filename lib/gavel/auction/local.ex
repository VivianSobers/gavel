defmodule Gavel.Auction.Local do
  @moduledoc """
  Local node interface for auction servers.
  """

  alias Gavel.Auction.Server

  @doc """
  Finds or starts an auction server and sends it a command with a 5-second timeout.
  """
  def command(auction_id, command) do
    with {:ok, pid} <- find_or_start_server(auction_id) do
      try do
        GenServer.call(pid, {:command, command}, 5_000)
      catch
        :exit, {{:shutdown, :not_found}, _} ->
          {:error, :not_found}

        :exit, {:shutdown, :not_found} ->
          {:error, :not_found}

        # The server stopped between lookup and call (for example after losing
        # the fence); the caller retries and gets a fresh server.
        :exit, {reason, _} when reason in [:noproc, :normal] ->
          {:error, :stale}
      end
    end
  end

  defp find_or_start_server(auction_id) do
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
