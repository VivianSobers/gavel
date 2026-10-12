defmodule Gavel.Clock.System do
  @moduledoc """
  System clock implementation returning current unix time in milliseconds.
  """

  @behaviour Gavel.Clock

  @impl true
  @spec now_ms() :: integer()
  def now_ms do
    System.system_time(:millisecond)
  end
end
