
defmodule Statement.Sql do
    @moduledoc"""
    Module for definition and construction of SQL statements
    """

    alias Type.Type

    #TODO!!!
    #todo: implement BETWEEN inside WHERE
    #todo: implement WITH before a query
    #todo: implement JOIN
    #todo: implement use of functions inside select and having
    #todo: implement GROUP BY
    #todo: implement HAVING


    ################
    ### Functions
    ################

    @doc"""
    Returns the concatenation operator. The `BETWEEN` operator is not expected.

    ### Parameter:

        - operator: Atom. Operator to convert. The possible values are:
            :eq     =       equal
            :neq    <>      not equal
            :gt     >       greater than
            :gte    >=      greater than or equal
            :lt     <       less than
            :lte    <=      less than or equal
            :like   LIKE    search for a pattern
            :in     IN      to specify multiple possible values for a column
            :and    AND     and
            :or     OR      or
            :on     ON      to join

            :inner_join     INNER JOIN          returns records that have matching values in both tables
            :left_join      LEFT OUTER JOIN     returns all records from the left table, and the matched records from the right table
            :right_join     RIGHT OUTER JOIN    returns all records from the right table, and the matched records from the left table
            :full_join      FULL OUTER JOIN     returns all records when there is a match in either left or right table

    ### Return:

        - String

    """
    def get_operator(:eq), do: " = "

    def get_operator(:eq_nil), do: " IS "

    def get_operator(:neq), do: " <> "

    def get_operator(:neq_nil), do: " IS NOT "

    def get_operator(:gt), do: " > "

    def get_operator(:gte), do: " >= "

    def get_operator(:lt), do: " < "

    def get_operator(:lte), do: " <= "

    def get_operator(:in), do: " IN "

    def get_operator(:like), do: " LIKE "

    def get_operator(:or), do: " OR "

    def get_operator(:and), do: " AND "

    def get_operator(:on), do: " ON "

    def get_operator(:inner_join), do: " INNER JOIN "

    def get_operator(:left_join), do: " LEFT OUTER JOIN "

    def get_operator(:right_join), do: " RIGHT OUTER JOIN "

    def get_operator(:full_join), do: " FULL OUTER JOIN "

    @doc"""
    Returns the known SQL function

    ### Parameter:

        - function_name: Atom. Name of SQL function to use. The possible values are:
            :timestamp  Function returns a datetime value based on a date or datetime value string, contains a time zone.
            :datetime   Function returns a datetime value based on a date or datetime value string
            :time       Function returns a time value based on a date or time value string
            :date       Function returns a time value based on a date or date value string

    ### Return:

        - String

    """
    def get_function(:timestamp), do: "TIMESTAMP"

    def get_function(:datetime), do: "DATETIME"

    def get_function(:date), do: "DATE"

    def get_function(:time), do: "TIME"

    ################
    ### Statement
    ################

    @doc"""
    Construct an instruction to generate a UUID

    ### Return:

        - String

    """
    def generate_uuid() do
        """
        SELECT GENERATE_UUID() AS uuid;
        """
    end

    @doc"""
    Construct an INSERT statement

    ### Parameters:

        - table_id: String. Name of the table to insert the data into.

        - values: List of tuples. List of values to insert. Each tuple is {column_name, associated_value_to_store}.

    ### Return:

        - String

    """
    def insert(table_id, values)
        when is_binary(table_id) and is_list(values) do
            [column_names, associated_values] =
                Enum.reduce(
                    values,
                    [[], []],
                    fn {col, val}, [cn, av] ->
                        [
                            List.insert_at(cn, -1, col),
                            List.insert_at(av, -1, val),
                        ]
                    end
                )
                |> Enum.map(fn list -> concatenates_to_string(list, ", ") end)

            "INSERT INTO #{table_id} (#{column_names}) VALUES (#{associated_values});"
    end

    @doc"""
    Combine multiple `INSERT` queries into a single one

    ### Parameters:

        - `queries`: [String]. List of insert clauses. It is assumed that they all belong to the same table

    ### Return:

        - String

    """
    def merge_inserts(queries) when is_list(queries) do

        split_by = "VALUES "
        prefix =
            queries
            |> hd()
            |> String.split(split_by)
            |> hd()
            |> Kernel.<>(split_by)

        values =
            queries
            |> Enum.map(fn query ->
                query
                |> String.split(split_by)
                |> List.last()
                |> String.trim_trailing(";")
            end)

        prefix <> Enum.join(values, ", ") <> ";"
    end

    @doc"""
    Construct an SELECT statement

    ### Parameters:

        - table_id: String. Name of the table.

        - columns_to_return: List of atoms | :all. Defines the columns to return. If the `all` atom is defined, all the columns of the table will be returned; otherwise, a list will be defined with those that interest

        - conditions. List of (list of tuple). If the value is a empty list, it will be assumed that the existence of the WHERE component is not desired. Otherwise, each tuple has the format {a, b, c} or {a, b, c, d} where

            - a: Atom. Column name.

            - b: t(). Value to compare.

            - c: Atom. Operation to use. Expect :eq, :eq_nil, :neq, :neq_nil, :gt, :gte, :lt, :lte, :in, :like. You can query get_operator/1.

            - d: Atom. Function to use.

        Each list of this parameter, its elements are concatenated by the first value defined in `operators` and the lists are related to each other by the second value defined in `operators`.

        - operators: List of size at most 2. List of connectors. if it has cardinality

            - 0 => length(conditions) = 0

            - 1 => length(conditions) = 1

            - 2 => length(conditions) > 1

    ### Return:

        - String

    """
    def select(table_id, columns_to_return \\ :all, conditions \\ [], operators \\ [])
        when is_binary(table_id) and
        (is_list(columns_to_return) or is_atom(columns_to_return)) and
        is_list(conditions) and
        is_list(operators) do

            columns_to_return_str = if columns_to_return == :all do
                "*"
            else
                concatenates_to_string(columns_to_return, ", ")
            end

            where_str = if Kernel.length(conditions) == 0 do
                ""
            else
                "WHERE #{concatenates_lists_to_string(conditions, operators)}"
            end

        "SELECT #{columns_to_return_str} FROM #{table_id} #{where_str};"
    end

    @doc"""
    Construct an UPDATE statement

    ### Parameters:

        - table_id: String. Name of the table.

        - changes: List of tuple of size 2 [{atom, t()}, ...]. Change list. Each tuple {A, B} indicates

            - A field to modify

            - B value to modify in field a

        - conditions. List of (list of tuple). If the value is a empty list, it will be assumed that the existence of the WHERE component is not desired. Otherwise, each tuple has the format {a, b, c} or {a, b, c, d} where

            - a: Atom. Column name.

            - b: t(). Value to compare.

            - c: Atom. Operation to use. Expect :eq, :eq_nil, :neq, :neq_nil, :gt, :gte, :lt, :lte, :in, :like. You can query get_operator/1.

            - d: Atom. Function to use.

        Each list of this parameter, its elements are concatenated by the first value defined in `operators` and the lists are related to each other by the second value defined in `operators`.

        - operators: List of size at most 2. List of connectors. if it has cardinality

            - 0 => length(conditions) = 0

            - 1 => length(conditions) = 1

            - 2 => length(conditions) > 1

    ### Return:

        - String

    """
    def update(table_id, changes, conditions \\ [], operators \\ [])
        when is_binary(table_id) and is_list(changes) and is_list(conditions) and is_list(operators) do

        changes_str = changes
                    |> Enum.map(fn {field, value} -> {field, value, :eq} end)
                    |> concatenates_to_string(", ")

        where_str = if Kernel.length(conditions) == 0 do
            ""
        else
            "WHERE #{concatenates_lists_to_string(conditions, operators)}"
        end

        "UPDATE #{table_id} SET #{changes_str} #{where_str};"
    end

    @doc"""
    Construct an DELETE statement

    ### Parameters:

        - table_id: String. Name of the table.

        - conditions. List of (list of tuple). If the value is a empty list, it will be assumed that the existence of the WHERE component is not desired. Otherwise, each tuple has the format {a, b, c} or {a, b, c, d} where

            - a: Atom. Column name.

            - b: t(). Value to compare.

            - c: Atom. Operation to use. Expect :eq, :eq_nil, :neq, :neq_nil, :gt, :gte, :lt, :lte, :in, :like. You can query get_operator/1.

            - d: Atom. Function to use.

        Each list of this parameter, its elements are concatenated by the first value defined in `operators` and the lists are related to each other by the second value defined in `operators`.

        - operators: List of size at most 2. List of connectors. if it has cardinality

            - 0 => length(conditions) = 0

            - 1 => length(conditions) = 1

            - 2 => length(conditions) > 1

    ### Return:

        - String

    """
    def delete(table_id)
        when is_binary(table_id) do
            "TRUNCATE TABLE #{table_id};"
    end

    def delete(table_id, conditions, operators \\ [])
        when is_binary(table_id) and is_list(conditions) and is_list(operators) do
            "DELETE FROM #{table_id} WHERE #{concatenates_lists_to_string(conditions, operators)};"
    end


    ################
    ### Helper functions
    ################

    #
    # Concatenates a list of values, through a defined operator
    #
    # ### Parameters:
    #
    #     - list: Can be:
    #
    #         - List of terms. For example: [:a, :b] or ["abc", 1, %{}]
    #
    #         - list of tuple of size 3 {atom, t(), atom}. The first value is the name of the column, the second is any value and the third is the relationship defined between the previous 2. The possible relations can be consulted in get_operator/1. Intended for conditions within the WHERE.
    #
    #         - list of tuple of size 4 {atom, t(), atom, atom}. The first three elements coincide with the previous one, but the fourth is the function to be applied by the first and second element.
    #
    #     - operator: String or Atom. Operator to concatenate the elements of the list. If it is an atom, it is converted to a string using the get_operator/1 function.
    #
    # ### Return:
    #
    #     - String
    #
    defp concatenates_to_string(list, operator)
        when is_list(list) and is_atom(operator) do
            concatenates_to_string(list, get_operator(operator))
    end

    defp concatenates_to_string(list, operator)
        when is_list(list) and is_binary(operator) do
            concatenates_to_string(list, operator, "")
    end

    defp concatenates_to_string([], _, acc) do
        acc
    end

    defp concatenates_to_string([e1, e2 | r], operator, acc) do
        concatenates_to_string([e1], operator, acc) <>
        operator <>
        concatenates_to_string([e2 | r], operator, acc)
    end

    defp concatenates_to_string([{column, value, :in = relation}], _, _) do
        value =
            value
            |> Enum.reduce("(  ", fn elem, acc ->
                acc <> Type.convert_for_bigquery(elem) <> ", "
            end)
            |> String.slice(0..-3)
            |> Kernel.<>(")")

        Type.convert_for_bigquery(column) <>
        get_operator(relation) <>
        value
    end

    defp concatenates_to_string([{column, value, relation}], _, _) do
        Type.convert_for_bigquery(column) <>
        get_operator(relation) <>
        Type.convert_for_bigquery(value)
    end

    defp concatenates_to_string([{column, value, relation, :datetime = function}], _, _) do
        get_function(function) <> "(" <> Type.convert_for_bigquery(column) <> ")" <>
        get_operator(relation) <>
        Type.convert_for_bigquery(value)
    end

    defp concatenates_to_string([{column, value, relation, function}], _, _) do
        get_function(function) <> "(" <> Type.convert_for_bigquery(column) <> ")" <>
        get_operator(relation) <>
        get_function(function) <> "(" <> Type.convert_for_bigquery(value) <> ")"
    end

    defp concatenates_to_string([e], _, _) do
        Type.convert_for_bigquery(e)
    end

    #
    # Concatenate lists of lists of values
    #
    # ### Parameters:
    #
    #     - list: List of (list of values). List of list of values to concatenate. To see the format of the ;list of values, see the documentation for the first parameter in `concatenates_to_string/2`.
    #
    #     - operators: List of size at most 2. List of connectors.
    #
    # ### Return:`
    #
    #     - String.
    #
    defp concatenates_lists_to_string(list, operators)
        when is_list(list) and is_list(operators) do

            [op1, op2 | _r] = operators
                        |> List.insert_at(-1, " UNDEFINED_INTERNAL_OPERATOR ")
                        |> List.insert_at(-1, " UNDEFINED_EXTERNAL_OPERATOR ")
            concatenates_lists_to_string(list, op1, op2)
    end

    defp concatenates_lists_to_string([], _, _) do
        ""
    end

    defp concatenates_lists_to_string([list], internal_op, _)
        when is_list(list) and (is_atom(internal_op) or is_binary(internal_op)) do
            "(" <> concatenates_to_string(list, internal_op) <> ")"
    end

    defp concatenates_lists_to_string(list, internal_op, external_op)
        when is_atom(external_op) do
            concatenates_lists_to_string(list, internal_op, get_operator(external_op))
    end

    defp concatenates_lists_to_string([l1, l2 | r], internal_op, external_op)
        when is_list(l1) and is_list(l2) and is_list(r) and
            (is_atom(internal_op) or is_binary(internal_op)) and is_binary(external_op) do


            concatenates_lists_to_string([l1], internal_op, external_op) <>
            external_op <>
            concatenates_lists_to_string([l2 | r], internal_op, external_op)
    end





end
