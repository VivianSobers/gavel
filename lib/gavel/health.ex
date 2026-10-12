defmodule Gavel.Health do
  @moduledoc """
  Database health checks.
  """

  @doc """
  Checks database connectivity by running a simple query.
  """
  def check do
    case Gavel.Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  end
end
