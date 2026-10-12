defmodule Gavel.Cluster.Rpc do
  @moduledoc """
  Remote procedure call wrapper around `:erpc`.
  """

  @doc """
  Calls `fun` in `module` on `node` with `args` and `timeout`.
  Returns the function call result, or `{:error, {:erpc, reason}}` on RPC failure.
  """
  def call(node, module, fun, args, timeout) do
    :erpc.call(node, module, fun, args, timeout)
  catch
    :error, {:erpc, reason} ->
      {:error, {:erpc, reason}}

    :exit, {:erpc, reason} ->
      {:error, {:erpc, reason}}
  end
end
