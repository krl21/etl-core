
defprotocol Genserver.Utils.PPostgresDb do
    @moduledoc"""
    Protocol oriented to load data from a table in a database in postgres
    """

    @doc"""
    Extracts the new information from a certain table and stores it in Bigquery

    ### Parameter:

        - business: Atom. Business to which the data points.

        - conn_odbc_pid: Process. Process connecting Elixir and ODBC.

    """
    @spec perform(atom, pid) :: any
    def perform(business, conn_odbc_pid)


end
