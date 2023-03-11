
defprotocol Genserver.Utils.PPostgresDb do
    @moduledoc"""
    Protocol oriented to load data from a table in a database in postgres
    """

    @doc"""
    Extracts the new rows from a certain table

    ### Parameter:

        - business: Atom. Business to which the data points.

    """
    @spec get_data(atom) :: any
    def get_data(business)

    @doc"""
    Extracts the new rows from a certain table

    ### Parameter:

        - batch: List of map. Payloads.

        - conn_odbc_pid: Process. Process connecting Elixir and ODBC.

    """
    @spec load(list, pid) :: any
    def load(batch, conn_odbc_pid)


end
