
defmodule Type.Type do
    @moduledoc"""
    Module for working with data types
    """

    import Type.PTypeOf

    @doc"""
    Converts a data to its equivalent of a defined type

    ### Parameters:

        -x. Data to convert.

        - to: Data type that `x` will be converted to.

    ### Return:

        - value | nil | Exception

    ### Examples:

        iex> Type.convert(2, :float)
        2.0

        iex> Type.convert("2", :integer)
        2

        iex>Type.convert("14", :integer)
        14Type.convert("chain", :map)

        iex> Type.convert("chain", :string)
        "chain"

        iex> Type.convert("chain", :map)
        (throw) "NotImplementedError => from `binary` to `map`"

        iex> Type.convert(1668036600542, :string_datetime)
        "2022-11-09T23:30:00.542Z"

    ### Special considerations:

        - Elixir built-in data types to work with: binary, nil, integer, float, atom, list, map, boolean.

        - Elixir's non-built-in data types to work with: DateTime

        - Elixir non-existent data types, but need to create its name:

            - string: Binary equivalent.

            - string_datetime: Equivalent to converting from an integer to a binary, in DateTime format.


    """
    def convert(x, to) do
        convert(x, type_of(x), to)
    end

    #
    # Same documentation as convert/2. The difference lies in the second parameter: data type of `x`, to allow matching
    #
    defp convert(x, t, t) do
        x
    end

    defp convert(x, :binary, t)
        when t == :string  or t == :string_datetime do
            x
    end

    defp convert(x, :binary, :integer) do
        x
        |> Integer.parse()
        |> case do
            {v, ""} -> v
            _ -> nil
        end
    end

    defp convert(x, :binary, :float) do
        x
        |> Float.parse()
        |> case do
            :error -> nil
            {v, ""} -> v
            _ ->
                x
                |> String.contains?(".")
                |> if do
                    x
                    |> String.replace(".", "")
                    |> convert(:float)
                else
                    nil
                end
        end
    end

    defp convert(x, :binary, datetime)
        when datetime in [:datetime, :DateTime, :timestamp] do
            x
            |> Timex.Parse.DateTime.Parser.parse("{ISO:Extended:Z}")
            |> case do
                {:ok, value} ->
                    value
                {:error, error} ->
                    raise("Error: Convert `#{x}` to `#{inspect datetime}`. Information: #{error}")
            end
    end

    defp convert(x, :binary, :boolean) do
        x
        |> String.to_atom()
        |> convert(:boolean)
    end

    defp convert(x, :binary, :atom) do
        x |> String.to_atom()
    end

    defp convert(x, :binary, :map) do
        x
        |> Poison.decode()
        |> case do
            {:ok, map} ->
                map
            {:error, error} ->
                raise("Error: Convert `#{x}` to `#{inspect :map}`. Information: #{error}")
        end
    end

    defp convert(x, :integer, :float) do
        x / 1
    end

    defp convert(x, :integer, :string) do
        x |> Integer.to_string()
    end

    defp convert(x, :integer, :string_datetime) do
        x
        |> DateTime.from_unix(:millisecond)
        |> case do
            {:ok, date} ->
                date
                |> Poison.encode!()
                |> Poison.decode!()
            {:error, error} ->
                raise("Error: Convert `#{x}` to `#{inspect :string_datetime}`. Information: #{error}")
        end
    end

    defp convert(x, :float, :integer) do
        trunc(x)
    end

    defp convert(x, :float, :string) do
        x |> Float.to_string()
    end

    defp convert(x, :nil, _any) do
        x
    end

    defp convert(x, :atom, :boolean) do
        case x do
            :true ->
                true
            :false ->
                false
            _ ->
                raise("Error: Convert `#{x}`(Boolean BigQuery) to `#{inspect :boolean}`")
        end
    end

    defp convert(x, :atom, :string) do
        x |> Atom.to_string()
    end

    defp convert(x, :list, :string) do
        x |> List.to_string()
    end

    defp convert(x, :map, :string) do
        x
        |> Map.to_list()
        |> convert(:string)
    end

    defp convert(x, datetime, :string)
        when datetime in [:datetime, :DateTime, :timestamp] do
            x
            |> Poison.encode!()
            |> Poison.decode!()
    end

    @doc"""
    Converts the data into a format understandable by BigQuery

    ### Parameter:

        - x: t(). Value.

    ### Return:

        - String

    """
    def convert_for_bigquery(x) when is_binary(x) do
        x = x
            |> String.replace("\n", " ")
            |> String.replace("'", "_")
            |> String.replace("'", "_")
            |> String.replace("ñ", "%n")
            |> String.replace("Ñ", "%N")
            |> String.replace("á", "%a")
            |> String.replace("Á", "%A")
            |> String.replace("é", "%e")
            |> String.replace("É", "%E")
            |> String.replace("í", "%i")
            |> String.replace("Í", "%i")
            |> String.replace("ó", "%o")
            |> String.replace("Ó", "%O")
            |> String.replace("ú", "%u")
            |> String.replace("Ú", "%U")

        "'#{x}'"
    end

    def convert_for_bigquery(x) when is_map(x) do
        if Timex.is_valid?(x) do
            "TIMESTAMP('#{x |> to_string}')"
        else
            x = x
                |> Poison.encode()
                |> elem(1)
                |> String.replace("'", "_")
                |> String.replace("ñ", "%n")
                |> String.replace("Ñ", "%N")
                |> String.replace("á", "%a")
                |> String.replace("Á", "%A")
                |> String.replace("é", "%e")
                |> String.replace("É", "%E")
                |> String.replace("í", "%i")
                |> String.replace("Í", "%i")
                |> String.replace("ó", "%o")
                |> String.replace("Ó", "%O")
                |> String.replace("ú", "%u")
                |> String.replace("Ú", "%U")
            "JSON '#{x}'"
        end
    end

    def convert_for_bigquery(x) when is_nil(x) do
        "NULL"
    end

    def convert_for_bigquery(x) do
        convert(x, :string)
    end



end
