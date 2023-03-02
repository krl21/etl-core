
defmodule Stuff do
    @moduledoc"""
    Useful functions
    """

    import Type.TypeOf

    @doc"""
    Converts a number to a string, with the particularity that if the number is one digit, it adds the zero before it

    ### Parameter:

        - n: Integer. Number to convert.

    ### Return:

        - String.

    """
    def integer_to_string_with_2_digits(n) when 1 <= n and n <= 9 do
        "0" <> Integer.to_string(n)
    end

    def integer_to_string_with_2_digits(n) do
        Integer.to_string(n)
    end

    @doc"""
    Converts a time in seconds to the understandable format hh:mm:ss

    ###Parameter:

        - time: Integer. Time in second.

    ### Return:

        - String

    """
    def convert_seconds_to_humans(time)
        when is_integer(time) and time >= 0 do
            hours = div(time, 3600)
            minutes = time - hours * 3600 |> div(60)
            seconds = time - hours * 3600 - minutes * 60

            "#{hours}h #{minutes}m #{seconds}s"
        end

    @doc"""
    Subtract between lists. It generalizes, and uses, the one implemented by Kernel.--/2.
    The difference is for when a term to "subtract" is a map; in this case its values are obtained and it is transformed into lists of tuples, applying the subtraction to them.

    ### Parameters:

        - l1: List of tuples of size 2. List of items.

        - l2: List of tuples of size 2. List of elements used to compare in `l1`. Those tuples that are the same are removed from `l1`.

    ### Return:

        - List of tuples of size 2

    """
    def list_subtraction(l1, l2) do
        l1 = Enum.sort(l1)
        l2 = Enum.sort(l2)
        recursive_list_subtraction(l1, l2, [])
    end

    defp recursive_list_subtraction([], _, acc) do
        acc
    end

    defp recursive_list_subtraction(l1, [], acc) do
        acc ++ l1
    end

    defp recursive_list_subtraction([{k, v} | r1], [{k, v} | r2], acc) do
        recursive_list_subtraction(r1, r2, acc)
    end

    defp recursive_list_subtraction([{k, v1} | r1], [{k, v2} | r2], acc) do
        v1 = case type_of(v1) do
                :map -> Enum.sort(v1) |> Map.new()
                :list -> Enum.sort(v1)
                _ -> v1
            end
        v2 = case type_of(v2) do
                :map -> Enum.sort(v2) |> Map.new()
                :list -> Enum.sort(v2)
                _ -> v2
            end

        if v2 == v1 do
            recursive_list_subtraction(r1, r2, acc)
        else
            recursive_list_subtraction(r1, r2, acc ++ [{k, v1}])
        end
    end

    defp recursive_list_subtraction([{k1, v1} | r], [{k2, _v} | _] = l, acc) when k1 < k2 do
        recursive_list_subtraction(r, l, acc ++ [{k1, v1}])
    end

    defp recursive_list_subtraction(l, [{_k, _v} | r], acc) do
        recursive_list_subtraction(l, r, acc)
    end

    @doc"""
    Takes the first elements of the list

    ### Parameters:

        - list: List. List.

        - n: Integer. Number of elements to be taken consecutively, starting with the first.

    ### Return:

        - {A, B} (A + B = list) where

            A List the first `n` elements of `list`

            B List of the remaining elements of `list`

    """
    def get_firsts(list, n)
        when is_list(list) and is_integer(n) and n >= 0 do
            get_firsts(list, n, [], 0)
    end

    defp get_firsts([], _, acc, _) do
        {acc, []}
    end

    defp get_firsts(list, n, acc, n) do
        {acc, list}
    end

    defp get_firsts([elem | r], n, acc, count) do
        get_firsts(r, n, acc ++ [elem], count + 1)
    end

    @doc"""
    Generates a random string with the symbols '0123456789abcdefghijklmnopqrstuvwxyz'

    ### Parameter:

        - len: Integer. Chain length.

    ### Return:

        - String.

    """
    def random_string_generate(len)
        when is_integer(len) and len > 0 do
        symbols = '0123456789abcdefghijklmnopqrstuvwxyz'
        symbol_count = Enum.count(symbols)
        for _ <- 1..len, into: "", do: <<Enum.at(symbols, :crypto.rand_uniform(0, symbol_count))>>
    end




end
