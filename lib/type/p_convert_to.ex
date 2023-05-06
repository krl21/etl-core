
defprotocol Type.PConvertTo do
    @moduledoc"""
    Protocol oriented to the definition of the function to convert from one data type to another
    """

    @doc"""
    Converts a value to the equivalent of the defined type

    ### Parameters:

        -x:t(). Value.

        - type: Atom. Data type to convert.

    ### Return:

        - type()

    """
    @spec convert_to(t, atom) :: any
    def convert_to(x, type)

end


defimpl Type.PConvertTo, for: Atom do
    def convert_to(x, :atom) do
        x
    end

    def convert_to(nil, _type) do
        nil
    end

    def convert_to(x, :boolean) do
        case x do
            :true ->
                true
            :false ->
                false
            _ ->
                raise("Error: Convert `#{x}`(Boolean BigQuery) to `#{inspect :boolean}`")
        end
    end

    def convert_to(x, :string) do
        x
        |> Atom.to_string()
    end
end

defimpl Type.PConvertTo, for: Integer do
    def convert_to(x, :integer) do
        x
    end

    def convert_to(x, :float) do
        x / 1
    end

    def convert_to(x, :string) do
        x
        |> Integer.to_string()
    end

    def convert_to(x, datetime)
        when datetime in [:datetime, :timestamp] do
            x
            |> DateTime.from_unix(:millisecond)
            |> case do
                {:ok, date} ->
                    date
                {:error, error} ->
                    raise("Error: Convert `#{x}` to `#{inspect :string_datetime}`. Information: #{error}")
            end
    end
end

defimpl Type.PConvertTo, for: Float do
    def convert_to(x, :float) do
        x
    end

    def convert_to(x, :integer) do
        trunc(x)
    end

    def convert_to(x, :string) do
        x
        |> Float.to_string()
    end
end

defimpl Type.PConvertTo, for: BitString do
    alias Type.PConvertTo, as: A

    def convert_to(x, binary)
        when binary in [:binary, :bitstring, :string] do
        x
    end

    def convert_to(x, :integer) do
        x
        |> Integer.parse()
        |> case do
            {y, ""} ->
                y
            _ ->
                raise("Error: Convert `#{x}` to `#{inspect :integer}`.")
        end
    end

    def convert_to(x, :float) do
        x
        |> String.split(".")
        |> List.last()
        |> Kernel.==("0")
        |> if do
            x
            |> String.slice(0..-2)
        else
            x
        end
        |> String.replace(".", "")
        |> Float.parse()
        |> case do
            {v, ""} ->
                v
            _ ->
                raise("Error: Convert `#{x}` to `#{inspect :float}`.")
        end
    end

    def convert_to(x, datetime)
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

    def convert_to(x, :boolean) do
        x
        |> String.to_atom()
        |> A.convert_to(:boolean)
    end

    def convert_to(x, :atom) do
        x
        |> String.to_atom()
    end

    def convert_to(x, type)
        when type in [:list, :map] do
        x
        |> Poison.decode!()
    end
end

defimpl Type.PConvertTo, for: Binary do
    alias Type.PConvertTo, as: A

    def convert_to(x, binary)
        when binary in [:binary, :bitstring, :string] do
        x
    end

    def convert_to(x, :integer) do
        x
        |> Integer.parse()
        |> case do
            {y, ""} ->
                y
            _ ->
                raise("Error: Convert `#{x}` to `#{inspect :integer}`.")
        end
    end

    def convert_to(x, :float) do
        x
        |> String.split(".")
        |> List.last()
        |> Kernel.==("0")
        |> if do
            x
            |> String.slice(0..-2)
        else
            x
        end
        |> String.replace(".", "")
        |> Float.parse()
        |> case do
            {v, ""} ->
                v
            _ ->
                raise("Error: Convert `#{x}` to `#{inspect :float}`.")
        end
    end

    def convert_to(x, datetime)
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

    def convert_to(x, :boolean) do
        x
        |> String.to_atom()
        |> A.convert_to(:boolean)
    end

    def convert_to(x, :atom) do
        x
        |> String.to_atom()
    end

    def convert_to(x, :map) do
        x
        |> Poison.decode()
        |> case do
            {:ok, map} ->
                map
            {:error, error} ->
                raise("Error: Convert `#{x}` to `#{inspect :map}`. Information: #{error}")
        end
    end

    def convert_to(x, type)
        when type in [:list, :map] do
        x
        |> Poison.decode!()
    end
end

defimpl Type.PConvertTo, for: List do
    def convert_to(x, :list) do
        x
    end

    def convert_to(x, :string) do
        x
        |> List.to_string()
    end
end

defimpl Type.PConvertTo, for: Map do
    def convert_to(x, :map) do
        x
    end

    def convert_to(x, :string) do
        x
        |> Poison.encode!()
    end
end

defimpl Type.PConvertTo, for: DateTime do
    def convert_to(x, datetime)
        when datetime in [:datetime, :DateTime, :timestamp] do
            x
    end

    def convert_to(x, :string) do
            x
            |> Poison.encode!()
            |> Poison.decode!()
    end
end

defimpl Type.PConvertTo, for: DateTime do
    def convert_to(x, :tuple) do
        x
    end

    def convert_to({{_, _, _}, {_, _, _}} = x, :string) do
        x
        |> Timex.to_datetime()
        |> Poison.encode!()
        |> Poison.decode!()
    end
end
