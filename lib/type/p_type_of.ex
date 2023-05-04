
defprotocol Type.PTypeOf do
    @moduledoc"""
    Protocol oriented to determine the data type of an object
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

defimpl Type.PTypeOf, for: Function do
    def type_of(_data), do: :function
end

defimpl Type.PTypeOf, for: Integer do
    def type_of(_data), do: :integer
end

defimpl Type.PTypeOf, for: Binary do
    def type_of(_data), do: :binary
end

defimpl Type.PTypeOf, for: BitString do
    def type_of(_data), do: :binary
end

defimpl Type.PTypeOf, for: List do
    def type_of(_data), do: :list
end

defimpl Type.PTypeOf, for: Map do
    def type_of(_data), do: :map
end

defimpl Type.PTypeOf, for: Float do
    def type_of(_data), do: :float
end

defimpl Type.PTypeOf, for: Atom do
    def type_of(nil), do: :nil
    def type_of(_data), do: :atom
end

defimpl Type.PTypeOf, for: Tuple do
    def type_of(_data), do: :tuple
end

defimpl Type.PTypeOf, for: Pid do
    def type_of(_data), do: :pid
end

defimpl Type.PTypeOf, for: Port do
    def type_of(_data), do: :port
end

defimpl Type.PTypeOf, for: Reference do
    @spec type_of(reference) :: :reference
    def type_of(_data), do: :reference
end
