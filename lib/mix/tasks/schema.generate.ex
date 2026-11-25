
defmodule Mix.Tasks.Schema.Generate do
    use Mix.Task

    @shortdoc "Generates pending schema-migration files for one or all configured entities"

    @moduledoc """
    Diffs each entity's current desired schema against its last generated
    snapshot and, when they differ, writes a new numbered migration file. Pure
    and offline — never touches BigQuery.

    ## Usage

        mix schema.generate
        mix schema.generate --module Entity.Record.Record
        mix schema.generate --module Entity.Record.Record --name add_check_digit

    With no `--module`, runs for every entity configured in
    `config :my_app, :schema_migrations, modules: [...]`.
    """

    alias DataModel.Schema.Generator
    alias Mix.Tasks.SchemaHelpers

    @impl Mix.Task
    def run(args) do
        Mix.Task.run("app.config")
        {opts, _rest, _invalid} = OptionParser.parse(args, strict: [module: :string, name: :string])

        otp_app = Mix.Project.config()[:app]
        priv_dir = SchemaHelpers.schema_migrations_dir()
        modules = SchemaHelpers.resolve_modules(otp_app, opts[:module])
        generate_opts = build_generate_opts(priv_dir, opts[:name])

        Enum.each(modules, fn module ->
            case Generator.generate(module, generate_opts) do
                {:no_changes, business_key} ->
                    Mix.shell().info("#{business_key}: sin cambios")

                {:generated, path} ->
                    Mix.shell().info("#{inspect(module)}: migración generada en #{path}")
            end
        end)
    end


    ################
    ### Helper functions
    ################

    #
    # Builds the opts passed to `Generator.generate/2`, including `:name` only
    # when `--name` was actually given.
    #
    # ### Parameters:
    #     - priv_dir: String.t().
    #     - name: String.t() | nil.
    #
    # ### Returns:
    #     - Keyword list.
    #
    defp build_generate_opts(priv_dir, nil), do: [priv_dir: priv_dir]
    defp build_generate_opts(priv_dir, name), do: [priv_dir: priv_dir, name: name]
end
