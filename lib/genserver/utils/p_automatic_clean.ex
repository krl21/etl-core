
defprotocol Genserver.Utils.PAutomaticClean do
    @moduledoc"""
    Definition of the method to be used for the automatic deletion of the repeated tuples, in the tables
    """


    @doc"""
    Removes from a certain table, the repeated rows

    To add the definition of an automatic cleanup, add the definition for the private methods.

    ### Parameters:

        - business: Atom. Define the business.

        - pid: Process. Process connecting Elixir and ODBC.

        - other_data: Tuple. Other data of interest.

    """
    @spec run(atom, pid, tuple) :: any
    def run(business, pid, other_data)


end
