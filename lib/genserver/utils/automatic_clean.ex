
defprotocol Genserver.Utils.AutomaticClean do

    @doc"""
    Removes from a certain table, the repeated rows

    To add the definition of an automatic cleanup, add the definition for the private methods.

    ### Parameters:

        - business: Atom. Define the business. Possible values:

            new_vehicles__record. Table to work: Tables.Bigquery.NewVehicles.Service.table_id()

            new_vehicles__task. Table to work: Tables.Bigquery.NewVehicles.Task.table_id()

        - pid: Process. Process connecting Elixir and ODBC.

    """
    def run(business, pid)


end
