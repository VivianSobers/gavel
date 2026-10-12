defmodule Gavel.Clock.Test do
  @moduledoc """
  Test clock double backed by an Agent.
  """

  @behaviour Gavel.Clock

  @doc """
  Starts the clock agent.
  """
  def start_link(initial_ms \\ 0) do
    case Agent.start_link(fn -> initial_ms end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def now_ms do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Sets the current clock time in milliseconds.
  """
  def set(ms) when is_integer(ms) do
    Agent.update(__MODULE__, fn _ -> ms end)
  end

  @doc """
  Advances the current clock time by delta milliseconds.
  """
  def advance(delta_ms) when is_integer(delta_ms) do
    Agent.update(__MODULE__, fn current -> current + delta_ms end)
  end
end
