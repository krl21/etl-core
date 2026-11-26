
defmodule DataModel.Schema.TypeMapping do
    @moduledoc """
    Single source of truth for the correspondence between `Struct.InfoAttr` value
    types (`:string`, `:integer`, ...) and BigQuery column types (`"STRING"`,
    `"INT64"`, ...).

    Every type an `InfoAttr` can declare must have an entry here, including the
    ones with no unambiguous BigQuery equivalent (`:map`, `:list`) — those are
    filled in manually below, so the chosen BigQuery representation lives in one
    place instead of being scattered as a per-field override.
    """

    @mapping %{
        string:   "STRING",
        integer:  "INT64",
        float:    "FLOAT64",
        boolean:  "BOOL",
        timestamp: "TIMESTAMP",
        date:     "DATE",
        time:     "TIME",
        datetime: "DATETIME",
        decimal:  "NUMERIC",
        map:      "JSON",
        list:     "STRING"
    }

    @doc """
    Resolves the BigQuery column type for a given `Struct.InfoAttr` value type.

    ### Parameters:
        - type: Atom. The `type` field of a `Struct.InfoAttr` (e.g. `:string`, `:map`).

    ### Returns:
        - String. The BigQuery column type (e.g. `"STRING"`, `"JSON"`).

    ### Raises:
        - ArgumentError. If `type` has no entry in `@mapping` — add it here before
          using it on an `InfoAttr`.
    """
    def resolve(type) when is_atom(type) do
        Map.fetch(@mapping, type)
        |> case do
            {:ok, bigquery_type} ->
                bigquery_type
            :error ->
                raise ArgumentError,
                    "No hay mapeo BigQuery para el tipo #{inspect(type)}. Agrégalo en #{inspect(__MODULE__)}."
        end
    end




end
