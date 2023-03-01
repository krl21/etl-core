
defprotocol Type.TypeOf do
    @moduledoc"""
    Module oriented to determine the data type of an object
    """

    @doc"""
    Determine the type of data

    ### Parameter:

        - data. t(): Data.

    ### Return:

        - Atom.

    ### Examples:

        iex> Type.type_of(1)
        :integer

        iex> Type.type_of(%{hello: "world"})
        :map

        iex> tmp = "string"
        iex> Type.type_of(tmp)
        :binary

    """
    def type_of(data)

end

defimpl Type.TypeOf, for: Function do
    def type_of(_data), do: :function
end

defimpl Type.TypeOf, for: Integer do
    def type_of(_data), do: :integer
end

defimpl Type.TypeOf, for: Binary do
    def type_of(_data), do: :binary
end

defimpl Type.TypeOf, for: BitString do
    def type_of(_data), do: :binary
end

defimpl Type.TypeOf, for: List do
    def type_of(_data), do: :list
end

defimpl Type.TypeOf, for: Map do
    def type_of(_data), do: :map
end

defimpl Type.TypeOf, for: Float do
    def type_of(_data), do: :float
end

defimpl Type.TypeOf, for: Atom do
    def type_of(nil), do: :nil
    def type_of(_data), do: :atom
end

defimpl Type.TypeOf, for: Tuple do
    def type_of(_data), do: :tuple
end

defimpl Type.TypeOf, for: Pid do
    def type_of(_data), do: :pid
end

defimpl Type.TypeOf, for: Port do
    def type_of(_data), do: :port
end

defimpl Type.TypeOf, for: Reference do
    @spec type_of(reference) :: :reference
    def type_of(_data), do: :reference
end
