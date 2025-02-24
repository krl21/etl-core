
defmodule Type.Type do
    @moduledoc"""
    Module for working with data types
    """

    import Type.PConvertTo


    @doc"""
    Converts a data to its equivalent of a defined type

    ### Parameters:
        - x: Data to convert.
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
        convert_to(x, to)
        # cond do
        #     to == :string -> convert_to(x, to) |> normalize_unicode_chars()
        #     true -> convert_to(x, to)
        # end
    end

    @doc"""
    Converts the data into a format understandable by BigQuery

    ### Parameter:
        - x: Value.

    ### Return:
        - String

    """
    def convert_for_bigquery(x) when is_binary(x) do
        x
        |> normalize_special_chars()
        |> escape_bigquery_string()
    end

    def convert_for_bigquery(x) when is_map(x) do
        try do
            x
            |> Map.get(:__struct__)
            |> case do
                struct when struct in [DateTime, NaiveDateTime] ->
                    "TIMESTAMP('#{to_string(x)}')"
                Date ->
                    "DATE('#{to_string(x)}')"
                Time ->
                    x
                    |> Time.to_erl()
                    |> time_to_bigquery()
                _ -> raise ""
            end
        rescue
            _ ->
                "JSON '#{x |> Poison.encode!() |> normalize_special_chars()}'"
        end
    end

    def convert_for_bigquery(nil), do: "NULL"
    def convert_for_bigquery(x), do: convert(x, :string)

    defp normalize_special_chars(str) do
        str
        |> String.replace("\n", " ")
        |> String.replace("\t", "")
        |> String.replace("'", "%r_%")
        |> String.replace("ñ", "%nn%")
        |> String.replace("Ñ", "%nN%")
        |> String.replace("á", "%aa%")
        |> String.replace("Á", "%aA%")
        |> String.replace("é", "%ee%")
        |> String.replace("É", "%eE%")
        |> String.replace("í", "%ii%")
        |> String.replace("Í", "%iI%")
        |> String.replace("ó", "%oo%")
        |> String.replace("Ó", "%oO%")
        |> String.replace("ú", "%uu%")
        |> String.replace("Ú", "%uU%")
        |> normalize_unicode_chars()
    end

    def normalize_unicode_chars(nil), do: nil
    def normalize_unicode_chars(str) do
        str
        |> String.replace("’", "%r_%")
        |> String.replace("\u{2010}", "-")
        |> String.replace("\u{2011}", "-")
        |> String.replace("\u{2012}", "-")
        |> String.replace("\u{2013}", "-")
        |> String.replace("\u{2014}", "-")
        |> String.replace("\u{2015}", "-")
        |> String.replace("\u{2018}", "%r_%") # '
        |> String.replace("\u{2019}", "%r_%") # '
        |> String.replace("\u{2032}", "%r_%") # '
        |> String.replace("\u{201C}", "\"")
        |> String.replace("\u{201D}", "\"")
        |> String.replace("\u{2033}", "\"")
        |> String.replace("\u{00AB}", "\"")
        |> String.replace("\u{00BB}", "\"")
        |> String.replace("\u{2039}", "%r_%") # '
        |> String.replace("\u{203A}", "%r_%") # '
        |> String.replace("\u{2026}", "...")
        |> String.replace("\u{00A0}", " ")
        |> String.replace("\u{2002}", " ")
        |> String.replace("\u{2003}", " ")
        |> String.replace("\u{2009}", " ")
        |> String.replace("\u{202F}", " ")
        |> String.replace("\u{205F}", " ")
        |> String.replace("\u{00AD}", "")
        |> String.replace("\u{200B}", "")
        |> String.replace("\u{FEFF}", "")
        |> String.replace("\u{2022}", "*")
        |> String.replace("\u{00B7}", "*")
        |> String.replace("\u{20AC}", "EUR")
        |> String.replace("\u{00A3}", "GBP")
        |> String.replace("\u{00A5}", "JPY")
        |> String.replace("\u{00A9}", "(c)")
        |> String.replace("\u{00AE}", "\(r\)")
        |> String.replace("\u{2122}", "\(tm\)")
        |> String.replace("\u{00B0}", "deg")
        |> String.replace("\u{00D7}", "x")
        |> String.replace("\u{00F7}", "/")
        |> String.replace("\u{00B1}", "+/-")
        |> String.replace("\u{00B5}", "u")
        |> String.replace("\u{00B6}", "P")
        |> String.replace("\u{00A7}", "S")
        |> String.replace("\u{2020}", "+")
        |> String.replace("\u{2021}", "++")
    end

    defp escape_bigquery_string(x), do:
        "'#{x}'"

    defp unescape_bigquery_string(x) do
        x
        |> String.replace("%r_%", "'")
        |> String.replace("%nn%", "ñ")
        |> String.replace("%nN%", "Ñ")
        |> String.replace("%aa%", "á")
        |> String.replace("%aA%", "Á")
        |> String.replace("%ee%", "é")
        |> String.replace("%eE%", "É")
        |> String.replace("%ii%", "í")
        |> String.replace("%iI%", "Í")
        |> String.replace("%oo%", "ó")
        |> String.replace("%oO%", "Ó")
        |> String.replace("%uu%", "ú")
        |> String.replace("%uU%", "Ú")
    end

    defp time_to_bigquery({h, m, s}), do:
        "TIME(#{h}, #{m}, #{s})"


    @doc """
    Convert bigquery text to understandable format

    ### Parameter:
        - x: t(). Value.

    ### Return:
        - String

    """
    def convert_from_bigquery(x) when is_binary(x), do:
        unescape_bigquery_string(x)



end




# defmodule Type.Type do
#     @moduledoc"""
#     Module for working with data types
#     """

#     import Type.PConvertTo


#     @doc"""
#     Converts a data to its equivalent of a defined type

#     ### Parameters:
#         - x. Data to convert.
#         - to: Data type that `x` will be converted to.

#     ### Return:
#         - value | nil | Exception

#     ### Examples:
#         iex> Type.convert(2, :float)
#         2.0

#         iex> Type.convert("2", :integer)
#         2

#         iex>Type.convert("14", :integer)
#         14Type.convert("chain", :map)

#         iex> Type.convert("chain", :string)
#         "chain"

#         iex> Type.convert("chain", :map)
#         (throw) "NotImplementedError => from `binary` to `map`"

#         iex> Type.convert(1668036600542, :string_datetime)
#         "2022-11-09T23:30:00.542Z"

#     ### Special considerations:
#         - Elixir built-in data types to work with: binary, nil, integer, float, atom, list, map, boolean.
#         - Elixir's non-built-in data types to work with: DateTime
#         - Elixir non-existent data types, but need to create its name:
#             - string: Binary equivalent.
#             - string_datetime: Equivalent to converting from an integer to a binary, in DateTime format.


#     """
#     def convert(x, to) do
#         convert_to(x, to)
#     end

#     @doc"""
#     Converts the data into a format understandable by BigQuery

#     ### Parameter:

#         - x: t(). Value.

#     ### Return:

#         - String

#     """
#     def convert_for_bigquery(x) when is_binary(x) do
#         x = x
#             |> String.replace("\n", " ")
#             |> String.replace("\t", "")
#             |> String.replace("'", "_")
#             |> String.replace("ñ", "%n")
#             |> String.replace("Ň", "Ñ")
#             |> String.replace("Ñ", "%N")
#             |> String.replace("á", "%a")
#             |> String.replace("Á", "%A")
#             |> String.replace("é", "%e")
#             |> String.replace("É", "%E")
#             |> String.replace("í", "%i")
#             |> String.replace("Í", "%i")
#             |> String.replace("ó", "%o")
#             |> String.replace("Ó", "%O")
#             |> String.replace("ú", "%u")
#             |> String.replace("Ú", "%U")
#             |> String.replace("–", "-")

#         "'#{x}'"
#     end

#     def convert_for_bigquery(x) when is_map(x) do
#         try do

#             x
#             |> Map.get(:__struct__)
#             |> case do
#                 struct when struct in [DateTime, NaiveDateTime] ->
#                     "TIMESTAMP('#{x |> to_string}')"

#                 Date ->
#                     "DATE('#{x |> to_string}')"

#                 Time ->
#                     {h, m, s} = x |> Time.to_erl()
#                     "TIME(#{h}, #{m}, #{s})"

#                 _map ->
#                     raise("")
#             end
#         rescue
#             _ ->
#                 x = x
#                 |> Poison.encode!()
#                 |> String.replace("\\t", "")
#                 |> String.replace("'", "_")
#                 |> String.replace("ñ", "%n")
#                 |> String.replace("Ñ", "%N")
#                 |> String.replace("á", "%a")
#                 |> String.replace("Á", "%A")
#                 |> String.replace("é", "%e")
#                 |> String.replace("É", "%E")
#                 |> String.replace("í", "%i")
#                 |> String.replace("Í", "%i")
#                 |> String.replace("ó", "%o")
#                 |> String.replace("Ó", "%O")
#                 |> String.replace("ú", "%u")
#                 |> String.replace("Ú", "%U")
#             "JSON '#{x}'"
#         end
#     end

#     def convert_for_bigquery(x) when is_nil(x) do
#         "NULL"
#     end

#     def convert_for_bigquery(x) do
#         convert(x, :string)
#     end

#     @doc"""
#     Convert bigquery text to understandable format

#     ### Parameter:

#         - x: t(). Value.

#     ### Return:

#         - String

#     """
#     def convert_from_bigquery(x) when is_binary(x) do
#         x
#         |> String.replace("_", "'")
#         |> String.replace("%n", "ñ")
#         |> String.replace("%N", "Ñ")
#         |> String.replace("%a", "á")
#         |> String.replace("%A", "Á")
#         |> String.replace("%e", "é")
#         |> String.replace("%E", "É")
#         |> String.replace("%i", "í")
#         |> String.replace("%i", "Í")
#         |> String.replace("%o", "ó")
#         |> String.replace("%O", "Ó")
#         |> String.replace("%u", "ú")
#         |> String.replace("%U", "Ú")
#     end



# end
