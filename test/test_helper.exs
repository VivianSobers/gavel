ExUnit.start(exclude: [:cluster])
Ecto.Adapters.SQL.Sandbox.mode(Gavel.Repo, :manual)
{:ok, _} = Gavel.Clock.Test.start_link()
