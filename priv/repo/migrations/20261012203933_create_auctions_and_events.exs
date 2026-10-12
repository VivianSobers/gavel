defmodule Gavel.Repo.Migrations.CreateAuctionsAndEvents do
  use Ecto.Migration

  def change do
    create table(:auctions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :text, null: false
      add :seller, :text, null: false
      add :config, :map, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:auctions, [:closed_at])

    create table(:events, primary_key: false) do
      add :auction_id, references(:auctions, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :seq, :integer, primary_key: true, null: false
      add :type, :text, null: false
      add :payload, :map, null: false
      add :request_id, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:events, [:auction_id, :request_id],
             where: "request_id IS NOT NULL",
             name: :events_auction_request_index
           )
  end
end
