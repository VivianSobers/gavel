defmodule Gavel.Repo do
  use Ecto.Repo,
    otp_app: :gavel,
    adapter: Ecto.Adapters.Postgres
end
