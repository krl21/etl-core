
defmodule PoolTest.PoolRecoveryTest do
    @moduledoc """
    Test para verificar la recuperación automática del pool de conexiones PostgreSQL cuando una conexión se cierra forzadamente durante un proceso.
    """

    require Logger

    @pool_name :test_recovery_pool
    @pool_size 3
    @total_concurrent_queries 30

    def run do
        Logger.configure(level: :info)
        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🧪 TEST: Pool Recovery - Verificar recuperación tras fallo de conexión")
        IO.puts(String.duplicate("=", 70))

        config = get_pg_config()

        IO.puts("\n📋 Configuración del test:")
        IO.puts("   • Pool size: #{@pool_size} conexiones")
        IO.puts("   • Host: #{config[:hostname]}:#{config[:port]}")
        IO.puts("   • Database: #{config[:database]}")

        # Iniciar el pool de prueba
        case start_test_pool(config) do
            {:ok, _pid} ->
                IO.puts("\n✅ Pool de prueba iniciado correctamente")
                run_recovery_test()

            {:error, reason} ->
                IO.puts("\n❌ Error iniciando pool: #{inspect(reason)}")
                System.halt(1)
        end
    end

    defp get_pg_config do
        %{
            hostname: System.get_env("PG_HOST"),
            port: String.to_integer(System.get_env("PG_PORT") || "5432"),
            database: System.get_env("PG_DATABASE"),
            username: System.get_env("PG_USERNAME"),
            password: System.get_env("PG_PASSWORD")
        }
    end

    defp start_test_pool(config) do
        children = [
            {Pool.Postgres,
                name: @pool_name,
                config: config,
                pool_size: @pool_size,
                queue_target: 1000,
                queue_interval: 10000
            }
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
    end

    defp run_recovery_test do
        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 1: Verificar que el pool funciona normalmente")
        IO.puts(String.duplicate("-", 70))

        case Pool.Postgres.query(@pool_name, "SELECT 1 as test", []) do
            {:ok, result} ->
                IO.puts("✅ Query de prueba exitosa: #{inspect(result.rows)}")

            {:error, reason} ->
                IO.puts("❌ Error en query de prueba: #{inspect(reason)}")
                System.halt(1)
        end

        # Obtener el PID del backend de PostgreSQL para verificar conexiones
        {:ok, initial_backends} = get_postgres_backends()
        IO.puts("📊 Backends PostgreSQL iniciales: #{length(initial_backends)}")

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 2: Obtener PID de conexión activa")
        IO.puts(String.duplicate("-", 70))

        # Ejecutar transacción para obtener el PID del backend de PostgreSQL
        {:ok, backend_pid} = Pool.Postgres.transaction(@pool_name, fn conn ->
            {:ok, result} = Postgrex.query(conn, "SELECT pg_backend_pid()", [])
            [[pid]] = result.rows
            IO.puts("🔍 PID del backend PostgreSQL: #{pid}")
            pid
        end)

        IO.puts("✅ Conexión identificada con backend PID: #{backend_pid}")

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 3: Simular fallo - Terminar conexión forzadamente")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n💥 Terminando conexión con pg_terminate_backend(#{backend_pid})...")

        # Usar otra conexión para terminar la primera
        # pg_terminate_backend termina la conexión especificada
        kill_result = Pool.Postgres.transaction(@pool_name, fn conn ->
            case Postgrex.query(conn, "SELECT pg_terminate_backend($1)", [backend_pid]) do
                {:ok, result} ->
                    [[terminated]] = result.rows
                    {:ok, terminated}
                {:error, reason} ->
                    {:error, reason}
            end
        end)

        case kill_result do
            {:ok, {:ok, true}} ->
                IO.puts("✅ Conexión terminada exitosamente")

            {:ok, {:ok, false}} ->
                IO.puts("⚠️  No se pudo terminar la conexión (puede que ya no exista)")

            {:ok, {:error, reason}} ->
                IO.puts("⚠️  Error al terminar: #{inspect(reason)}")

            {:error, reason} ->
                IO.puts("⚠️  Error en transacción de terminación: #{inspect(reason)}")
        end

        # Esperar un momento para que el pool detecte la desconexión
        IO.puts("\n⏳ Esperando 2 segundos para que el pool detecte el fallo...")
        Process.sleep(2_000)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 4: Verificar recuperación del pool")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n🔄 Intentando ejecutar queries después del fallo...")

        # Ejecutar varias queries para verificar que el pool funciona
        results = for i <- 1..@total_concurrent_queries do
            case Pool.Postgres.query(@pool_name, "SELECT $1::int as query_num, pg_backend_pid() as backend", [i]) do
                {:ok, result} ->
                    [[num, pid]] = result.rows
                    IO.puts("   ✅ Query #{num}: exitosa (backend PID: #{pid})")
                    {:ok, num, pid}

                {:error, reason} ->
                    IO.puts("   ❌ Query #{i}: fallida - #{inspect(reason)}")
                    {:error, i, reason}
            end
        end

        successful = Enum.count(results, fn {status, _, _} -> status == :ok end)
        failed = Enum.count(results, fn {status, _, _} -> status == :error end)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 5: Verificar estado final")
        IO.puts(String.duplicate("-", 70))

        {:ok, final_backends} = get_postgres_backends()
        IO.puts("\n📊 Backends PostgreSQL finales: #{length(final_backends)}")

        # Verificar que hay nuevas conexiones (los PIDs deberían ser diferentes)
        new_pids = Enum.filter(final_backends, fn pid -> pid != backend_pid end)
        IO.puts("📊 Nuevos backends (diferentes al original): #{length(new_pids)}")

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 RESULTADOS")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n📈 Resumen de queries post-fallo:")
        IO.puts("   • Exitosas: #{successful}/5")
        IO.puts("   • Fallidas: #{failed}/5")

        cond do
            successful == 5 ->
                IO.puts("\n🎯 COMPORTAMIENTO ESPERADO:")
                IO.puts("   ✅ El pool se recuperó completamente después del fallo")
                IO.puts("   ✅ Postgrex/DBConnection reconectó automáticamente")
                IO.puts("   ✅ Las queries subsiguientes funcionaron correctamente")

            successful > 0 ->
                IO.puts("\n⚠️  RECUPERACIÓN PARCIAL:")
                IO.puts("   El pool se recuperó parcialmente.")
                IO.puts("   Algunas queries fallaron, posiblemente durante la reconexión.")

            true ->
                IO.puts("\n❌ FALLO EN RECUPERACIÓN:")
                IO.puts("   El pool no pudo recuperarse del fallo.")
                IO.puts("   Esto puede indicar un problema de configuración.")
        end

        # Test adicional: Verificar que podemos hacer transacciones
        IO.puts("\n🔄 Test adicional: Ejecutando transacción completa...")

        case Pool.Postgres.transaction(@pool_name, fn conn ->
            Postgrex.query!(conn, "SELECT 'transaccion_exitosa'::text", [])
        end) do
            {:ok, result} ->
                IO.puts("   ✅ Transacción exitosa: #{inspect(result.rows)}")

            {:error, reason} ->
                IO.puts("   ❌ Transacción fallida: #{inspect(reason)}")
        end

        # Limpiar
        Supervisor.stop(__MODULE__.Supervisor)

        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🏁 Test completado")
        IO.puts(String.duplicate("=", 70) <> "\n")
    end

    # Obtiene los PIDs de los backends de PostgreSQL conectados desde esta aplicación
    defp get_postgres_backends do
        case Pool.Postgres.query(@pool_name, """
            SELECT pid
            FROM pg_stat_activity
            WHERE datname = current_database()
            AND pid != pg_backend_pid()
            AND application_name != ''
            ORDER BY backend_start
        """, []) do
            {:ok, result} ->
                pids = Enum.map(result.rows, fn [pid] -> pid end)
                {:ok, pids}

            {:error, reason} ->
                {:error, reason}
        end
    end
end

# Ejecutar el test
PoolTest.PoolRecoveryTest.run()
