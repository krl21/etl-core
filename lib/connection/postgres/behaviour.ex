
defmodule Connection.Postgres.Behaviour do
    @moduledoc """
    Contract mirroring `Connection.Postgres`'s public API, so a test double can
    be generated with `Mox.defmock/2` and swapped in via `EtlCore.Deps.postgres/0`.
    """

    @callback connect(config :: map()) :: {:ok, term()} | {:error, term()}
    @callback disconnect(conn :: term()) :: :ok
    @callback table_exists?(conn :: term(), table_name :: String.t()) :: {:ok, boolean()} | {:error, term()}
    @callback create_table_if_not_exists(conn :: term(), table_name :: String.t()) :: :ok | {:error, term()}
    @callback create_table_if_not_exists(conn :: term(), table_name :: String.t(), column_comments :: map()) :: :ok | {:error, term()}
    @callback drop_table(conn :: term(), table_name :: String.t()) :: :ok | {:error, term()}
    @callback insert(conn :: term(), table_name :: String.t(), record :: map()) :: {:ok, term()} | {:error, term()}
    @callback insert_many(conn :: term(), table_name :: String.t(), records :: [map()]) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback get_pending_bq(conn :: term(), table_name :: String.t(), register_type :: String.t() | nil, opts :: keyword()) :: {:ok, list()} | {:error, term()}
    @callback get_all(conn :: term(), table_name :: String.t(), limit :: non_neg_integer() | nil) :: {:ok, list()} | {:error, term()}
    @callback delete_by_ids(conn :: term(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_sent_to_bq(conn :: term(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_sent_to_bq_by_id_nodos(conn :: term(), table_name :: String.t(), id_nodos :: list(), register_type :: String.t() | nil) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_with_problems(conn :: term(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback delete_analyzed_records(conn :: term(), table_name :: String.t(), opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback dual_mode?(conn :: term()) :: boolean()
    @callback connection_info(conn :: term()) :: map()
    @callback query_flexible(conn :: term(), table_name :: String.t(), opts :: keyword()) :: {:ok, list()} | {:error, term()}
end
