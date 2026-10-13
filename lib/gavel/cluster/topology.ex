defmodule Gavel.Cluster.Topology do
  @moduledoc """
  Constructs libcluster topology specifications from environment configuration.
  """

  @doc """
  Parses a comma-separated node list into a libcluster topology keyword list.

  Returns `[]` when given nil or an empty string.
  """
  def from_env(nil), do: []

  def from_env(nodes_str) when is_binary(nodes_str) do
    hosts =
      nodes_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)

    case hosts do
      [] ->
        []

      _ ->
        [
          gavel: [
            strategy: Cluster.Strategy.Epmd,
            config: [hosts: hosts]
          ]
        ]
    end
  end
end
