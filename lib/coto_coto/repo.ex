defmodule CotoCoto.Repo do
  use Ecto.Repo,
    otp_app: :coto_coto,
    adapter: Ecto.Adapters.Postgres
end
