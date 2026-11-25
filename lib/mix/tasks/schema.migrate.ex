
defmodule Mix.Tasks.Schema.Migrate do
    use Mix.Task

    @shortdoc "Applies pending schema migrations to BigQuery"

    @moduledoc """
    Applies every pending schema migration (written by `mix schema.generate`)
    against BigQuery, fully automatically — there is no manual-approval gate.
    Stops at the first entity whose migration fails, so this can be used as a
    deploy-blocking pipeline step.

    ## Usage

        mix schema.migrate
        mix schema.migrate --module Entity.Record.Record

    Invokable from a CI pipeline step (its intended use) or run by hand — both
    run the exact same code as `DataModel.Schema.Migrator.migrate_all/4`.

    With no `--module`, runs for every entity configured in
    `config :my_app, :schema_migrations, modules: [...]`.
    """

    alias DataModel.Schema.Migrator
    alias Mix.Tasks.SchemaHelpers

    @impl Mix.Task
    def run(args) do
        Mix.Task.run("app.config")
        {opts, _rest, _invalid} = OptionParser.parse(args, strict: [module: :string])

        otp_app = Mix.Project.config()[:app]
        priv_dir = SchemaHelpers.schema_migrations_dir()
        control_table = SchemaHelpers.control_table_name(otp_app)
        modules = SchemaHelpers.resolve_modules(otp_app, opts[:module])
        data_source = Application.get_env(otp_app, :bigquery)[:configuration]

        EtlCore.Deps.odbc().start()
        pid = EtlCore.Deps.odbc().connect(data_source)

        try do
            pid
            |> Migrator.migrate_all(modules, priv_dir, control_table)
            |> report_result()
        after
            EtlCore.Deps.odbc().disconnect(pid)
        end
    end


    ################
    ### Helper functions
    ################

    #
    # Prints `Migrator.migrate_all/4`'s result and halts the task with a
    # non-zero status on failure, so a CI pipeline step reliably fails too.
    #
    # ### Parameters:
    #     - result: {:ok, [{module(), [pos_integer()]}]} | {:error, module(), pos_integer(), String.t()}.
    #
    # ### Returns:
    #     - :ok.
    #
    defp report_result({:ok, results}) do
        Enum.each(results, fn {module, applied} ->
            Mix.shell().info("#{inspect(module)}: aplicadas #{inspect(applied)}")
        end)
    end

    defp report_result({:error, module, version, reason}) do
        Mix.shell().error("#{inspect(module)}: migración #{version} falló: #{reason}")
        System.halt(1)
    end
end
