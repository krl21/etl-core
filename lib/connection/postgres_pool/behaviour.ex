
defmodule Connection.PostgresPool.Behaviour do
    @moduledoc """
    Contract mirroring `Connection.PostgresPool`'s public API, so a test double
    can be generated with `Mox.defmock/2` and swapped in via `EtlCore.Deps.postgres_pool/0`.
    """

    @callback table_exists?(pool_name :: atom(), table_name :: String.t()) :: {:ok, boolean()} | {:error, term()}
    @callback create_table_if_not_exists(pool_name :: atom(), table_name :: String.t()) :: :ok | {:error, term()}
    @callback create_table_if_not_exists(pool_name :: atom(), table_name :: String.t(), column_comments :: map()) :: :ok | {:error, term()}
    @callback drop_table(pool_name :: atom(), table_name :: String.t()) :: :ok | {:error, term()}
    @callback insert(pool_name :: atom(), table_name :: String.t(), record :: map()) :: {:ok, term()} | {:error, term()}
    @callback insert_many(pool_name :: atom(), table_name :: String.t(), records :: [map()]) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback get_pending_bq(pool_name :: atom(), table_name :: String.t(), register_type :: String.t() | nil, opts :: keyword()) :: {:ok, list()} | {:error, term()}
    @callback get_all(pool_name :: atom(), table_name :: String.t(), limit :: non_neg_integer() | nil) :: {:ok, list()} | {:error, term()}
    @callback delete_all(pool_name :: atom(), table_name :: String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback delete_by_ids(pool_name :: atom(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_sent_to_bq(pool_name :: atom(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_sent_to_bq_by_id_nodos(pool_name :: atom(), table_name :: String.t(), id_nodos :: list(), register_type :: String.t() | nil) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback mark_as_with_problems(pool_name :: atom(), table_name :: String.t(), ids :: list()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback delete_analyzed_records(pool_name :: atom(), table_name :: String.t(), opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
    @callback query_flexible(pool_name :: atom(), table_name :: String.t(), opts :: keyword()) :: {:ok, list()} | {:error, term()}
end
