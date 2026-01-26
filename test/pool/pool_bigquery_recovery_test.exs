
defmodule PoolTest.PoolBigQueryRecoveryTest do
    @moduledoc """
    Test para verificar la recuperación automática del pool de conexiones BigQuery (poolboy)
    cuando un worker se cierra forzadamente durante un proceso.
    """

    require Logger

    @pool_name :test_bq_recovery_pool
    @pool_size 10
    @max_overflow 1
    @total_concurrent_queries 20


    def run do
        Logger.configure(level: :info)
        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🧪 TEST: BigQuery Pool Recovery - Verificar recuperación tras fallo")
        IO.puts(String.duplicate("=", 70))

        data_source = get_bq_config()

        IO.puts("\n📋 Configuración del test:")
        IO.puts("   • Pool size: #{@pool_size} conexiones")
        IO.puts("   • Max overflow: #{@max_overflow}")
        IO.puts("   • DSN: #{inspect(data_source[:dsn])}")

        # Iniciar ODBC primero
        IO.puts("\n🔌 Iniciando ODBC...")
        Connection.Odbc.start()

        # Iniciar el pool de prueba
        case start_test_pool(data_source) do
            {:ok, _pid} ->
                IO.puts("✅ Pool de prueba iniciado correctamente")
                run_recovery_test()

            {:error, reason} ->
                IO.puts("\n❌ Error iniciando pool: #{inspect(reason)}")
                System.halt(1)
        end
    end

    defp get_bq_config do
        [
            dsn: System.get_env("DNS"),
            warehouse: System.get_env("DATAMART_NEW_VEHICLES")
        ]
    end

    defp start_test_pool(data_source) do
        children = [
            {Pool.BigQuery,
                name: @pool_name,
                data_source: data_source,
                pool_size: @pool_size,
                max_overflow: @max_overflow
            }
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
    end

    defp run_recovery_test do
        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 1: Verificar que el pool funciona normalmente")
        IO.puts(String.duplicate("-", 70))

        # Mostrar estadísticas iniciales del pool
        show_pool_stats("Inicial")

        # Test básico de conectividad
        case test_basic_query() do
            {:ok, _} ->
                IO.puts("✅ Query de prueba exitosa")

            {:error, reason} ->
                IO.puts("❌ Error en query de prueba: #{inspect(reason)}")
                System.halt(1)
        end

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 2: Identificar workers del pool")
        IO.puts(String.duplicate("-", 70))

        # Obtener los PIDs de los workers actuales
        initial_workers = get_pool_workers()
        IO.puts("\n📋 Workers actuales en el pool:")
        Enum.each(initial_workers, fn pid ->
            IO.puts("   • #{inspect(pid)} (alive: #{Process.alive?(pid)})")
        end)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 3: Simular fallo - Terminar un worker forzadamente")
        IO.puts(String.duplicate("-", 70))

        # Tomar el primer worker y terminarlo
        worker_to_kill = List.first(initial_workers)

        if worker_to_kill do
            IO.puts("\n💥 Terminando worker: #{inspect(worker_to_kill)}")

            # Terminar el worker forzadamente
            Process.exit(worker_to_kill, :kill)

            IO.puts("✅ Señal de kill enviada")

            # Esperar un momento para que poolboy detecte y reemplace el worker
            IO.puts("\n⏳ Esperando 2 segundos para que poolboy reemplace el worker...")
            Process.sleep(2_000)

            # Mostrar estadísticas después del kill
            show_pool_stats("Después del kill")

            # Verificar estado del worker terminado
            IO.puts("\n🔍 Estado del worker terminado:")
            IO.puts("   • #{inspect(worker_to_kill)} alive: #{Process.alive?(worker_to_kill)}")
        else
            IO.puts("⚠️  No se encontraron workers para terminar")
        end

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 4: Verificar recuperación del pool")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n🔄 Ejecutando operaciones después del fallo...")

        # Ejecutar varias operaciones para verificar que el pool funciona
        results = for i <- 1..(@total_concurrent_queries + 3) do
            case Pool.BigQuery.with_connection_safe(@pool_name, fn conn ->
                Connection.Odbc.select(conn, "SELECT #{i} as query_num")
            end) do
                {:ok, result} ->
                    IO.puts("   ✅ Query #{i}: exitosa")
                    {:ok, i, result}

                {:error, reason} ->
                    IO.puts("   ❌ Query #{i}: fallida - #{inspect(reason)}")
                    {:error, i, reason}
            end
        end

        successful = Enum.count(results, fn {status, _, _} -> status == :ok end)
        failed = Enum.count(results, fn {status, _, _} -> status == :error end)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 5: Verificar estado final del pool")
        IO.puts(String.duplicate("-", 70))

        # Obtener workers finales
        final_workers = get_pool_workers()
        IO.puts("\n📋 Workers finales en el pool:")
        Enum.each(final_workers, fn pid ->
            IO.puts("   • #{inspect(pid)} (alive: #{Process.alive?(pid)})")
        end)

        # Mostrar estadísticas finales
        show_pool_stats("Final")

        # Verificar si hay nuevos workers (reemplazos)
        new_workers = final_workers -- initial_workers
        IO.puts("\n📊 Nuevos workers (reemplazos): #{length(new_workers)}")
        Enum.each(new_workers, fn pid ->
            IO.puts("   • #{inspect(pid)} (nuevo)")
        end)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 RESULTADOS")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n📈 Resumen de operaciones post-fallo:")
        IO.puts("   • Exitosas: #{successful}/#{@pool_size + 2}")
        IO.puts("   • Fallidas: #{failed}/#{@pool_size + 2}")

        cond do
            successful == (@pool_size + 2) ->
                IO.puts("\n🎯 COMPORTAMIENTO ESPERADO:")
                IO.puts("   ✅ El pool se recuperó completamente después del fallo")
                IO.puts("   ✅ Poolboy reemplazó automáticamente el worker caído")
                IO.puts("   ✅ Las operaciones subsiguientes funcionaron correctamente")

            successful > 0 ->
                IO.puts("\n⚠️  RECUPERACIÓN PARCIAL:")
                IO.puts("   El pool se recuperó parcialmente.")
                IO.puts("   Algunas operaciones fallaron durante la recuperación.")

            true ->
                IO.puts("\n❌ FALLO EN RECUPERACIÓN:")
                IO.puts("   El pool no pudo recuperarse del fallo.")
        end

        # Test adicional: Verificar que podemos hacer operaciones concurrentes
        IO.puts("\n🔄 Test adicional: Ejecutando operaciones concurrentes...")

        concurrent_results = 1..@pool_size
        |> Enum.map(fn i ->
            Task.async(fn ->
                Pool.BigQuery.with_connection_safe(@pool_name, fn conn ->
                    Connection.Odbc.select(conn, "SELECT #{i} as concurrent_test")
                end, timeout: 10_000)
            end)
        end)
        |> Enum.map(&Task.await(&1, 15_000))

        concurrent_success = Enum.count(concurrent_results, &match?({:ok, _}, &1))
        IO.puts("   ✅ Operaciones concurrentes exitosas: #{concurrent_success}/#{@pool_size}")

        # Limpiar
        Supervisor.stop(__MODULE__.Supervisor)

        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🏁 Test completado")
        IO.puts(String.duplicate("=", 70) <> "\n")
    end

    defp test_basic_query do
        Pool.BigQuery.with_connection_safe(@pool_name, fn conn ->
            Connection.Odbc.select(conn, "SELECT 1 as test")
        end, timeout: 5_000)
    end

    defp show_pool_stats(label) do
        stats = Pool.BigQuery.pool_stats(@pool_name)
        IO.puts("\n📈 Pool Stats (#{label}):")
        IO.puts("   • Estado: #{inspect(stats[:state])}")
        IO.puts("   • Workers disponibles: #{stats[:available_workers]}")
        IO.puts("   • Workers overflow: #{stats[:overflow_workers]}")
        IO.puts("   • Checked out: #{stats[:checked_out]}")
    end

    defp get_pool_workers do
        # Obtener los workers de poolboy usando :sys.get_state
        # El estado de poolboy tiene la estructura {state, available, overflow, ...}
        try do
            pool_pid = Process.whereis(@pool_name)

            if pool_pid do
                # Poolboy mantiene los workers en su estado interno
                # Podemos obtenerlos ejecutando operaciones y capturando el caller
                workers = for _ <- 1..@pool_size do
                    try do
                        :poolboy.transaction(@pool_name, fn worker_pid ->
                            worker_pid
                        end, 1_000)
                    catch
                        :exit, _ -> nil
                    end
                end

                workers
                |> Enum.reject(&is_nil/1)
                |> Enum.uniq()
            else
                []
            end
        rescue
            _ -> []
        end
    end
end

# Ejecutar el test
PoolTest.PoolBigQueryRecoveryTest.run()
