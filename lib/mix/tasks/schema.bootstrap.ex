
defmodule Mix.Tasks.Schema.Bootstrap do
    use Mix.Task

    @shortdoc "Writes the schema-migration baseline for an already-existing BigQuery table"

    @moduledoc """
    Establishes the `_schema.json` baseline for one or more entities whose
    BigQuery table already exists (created manually, outside this system) —
    without generating a migration file and without contacting BigQuery.

    Must be run once per pre-existing entity before its first real
    `mix schema.generate`; brand-new entities (no table yet) don't need
    it — their first `generate` naturally produces a `:create_table`
    migration.

    ## Usage

        mix schema.bootstrap
        mix schema.bootstrap --module Entity.Record.Record

    With no `--module`, bootstraps every entity configured in
    `config :my_app, :schema_migrations, modules: [...]`.
    """

    alias DataModel.Schema.Generator
    alias Mix.Tasks.SchemaHelpers

    @impl Mix.Task
    def run(args) do
        Mix.Task.run("app.config")
        {opts, _rest, _invalid} = OptionParser.parse(args, strict: [module: :string])

        otp_app = Mix.Project.config()[:app]
        priv_dir = SchemaHelpers.schema_migrations_dir()
        modules = SchemaHelpers.resolve_modules(otp_app, opts[:module])

        Enum.each(modules, fn module ->
            {:bootstrapped, business_key} = Generator.bootstrap(module, priv_dir: priv_dir)
            Mix.shell().info("#{business_key}: schema baseline escrito (#{inspect(module)})")
        end)
    end
end
