
defmodule PoolTest.PoolBigQueryExhaustionTest do
    @moduledoc """
    Test para verificar el comportamiento del pool de conexiones BigQuery (poolboy + ODBC) cuando todas las conexiones están siendo utilizadas.
    """

    require Logger

    @pool_name :test_bq_exhaustion_pool
    @pool_size 10
    @max_overflow 0              # Sin overflow para probar saturación real
    @total_concurrent_queries 20
    @hold_time_ms 5_000          # Tiempo que cada conexión se retiene (5 segundos)

    def run do
        Logger.configure(level: :info)
        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🧪 TEST: BigQuery Pool Exhaustion - Verificar comportamiento saturado")
        IO.puts(String.duplicate("=", 70))

        data_source = get_bq_config()

        IO.puts("\n📋 Configuración del test:")
        IO.puts("   • Pool size: #{@pool_size} conexiones")
        IO.puts("   • Max overflow: #{@max_overflow}")
        IO.puts("   • Tiempo de retención por conexión: #{@hold_time_ms}ms")
        IO.puts("   • Timeout para checkout: #{@checkout_timeout_ms}ms")
        IO.puts("   • DSN: #{inspect(data_source[:dsn])}")

        # Iniciar ODBC primero
        IO.puts("\n🔌 Iniciando ODBC...")
        Connection.Odbc.start()

        # Iniciar el pool de prueba
        case start_test_pool(data_source) do
            {:ok, _pid} ->
                IO.puts("✅ Pool de prueba iniciado correctamente")
                run_exhaustion_test()

            {:error, reason} ->
                IO.puts("\n❌ Error iniciando pool: #{inspect(reason)}")
                System.halt(1)
        end
    end

    defp get_bq_config do
        [
            dsn: System.get_env("DNS") || System.get_env("DSN"),
            warehouse: System.get_env("DATAMART_NEW_VEHICLES") || "test_warehouse"
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

    defp run_exhaustion_test do
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
        IO.puts("📊 FASE 2: Saturar el pool - Tomar TODAS las conexiones")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n🔒 Iniciando #{@total_concurrent_queries} operaciones que retendrán las conexiones...")

        # Crear tareas que toman todas las conexiones y las retienen
        holder_tasks = for i <- 1..@total_concurrent_queries do
            Task.async(fn ->
                connection_holder(i)
            end)
        end

        # Esperar un momento para asegurar que las conexiones fueron tomadas
        Process.sleep(500)

        # Mostrar estadísticas con conexiones ocupadas
        show_pool_stats("Con #{@total_concurrent_queries} conexiones ocupadas")

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 3: Intentar operación adicional (debería esperar)")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n⏳ Intentando ejecutar operación con pool saturado...")
        IO.puts("   (Debería esperar hasta que una conexión se libere)\n")

        # Medir el tiempo que tarda en ejecutarse la operación
        start_time = System.monotonic_time(:millisecond)

        # Intentar ejecutar una operación adicional
        operation_task = Task.async(fn ->
            simulate_bq_operation()
        end)

        # Mientras esperamos, mostrar progreso
        monitor_task = Task.async(fn ->
            monitor_waiting_operation(start_time)
        end)

        # Esperar a que termine el monitor
        Task.await(monitor_task, @hold_time_ms + 10_000)

        operation_result = Task.await(operation_task, @checkout_timeout_ms + 10_000)
        end_time = System.monotonic_time(:millisecond)

        # Esperar a que las tareas de retención terminen
        Enum.each(holder_tasks, fn task ->
            Task.await(task, @hold_time_ms + 5_000)
        end)

        # Mostrar estadísticas finales
        show_pool_stats("Final (todas liberadas)")

        # Mostrar resultados
        show_results(operation_result, end_time - start_time)

        # Limpiar
        Supervisor.stop(__MODULE__.Supervisor)

        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🏁 Test completado")
        IO.puts(String.duplicate("=", 70) <> "\n")
    end

    defp test_basic_query do
        Pool.BigQuery.with_connection_safe(@pool_name, fn conn ->
            # Query simple para verificar conectividad
            Connection.Odbc.query(conn, "SELECT 1 as test")
        end, timeout: 5_000)
    end

    defp connection_holder(id) do
        IO.puts("   🔐 Worker #{id}: Solicitando conexión...")

        try do
            Pool.BigQuery.with_connection(@pool_name, fn conn ->
                IO.puts("   🔐 Worker #{id}: ✅ Conexión obtenida, reteniendo por #{@hold_time_ms}ms")

                # Hacer una query simple para verificar que la conexión funciona
                Connection.Odbc.query(conn, "SELECT #{id} as worker_id")

                # Retener la conexión
                Process.sleep(@hold_time_ms)

                IO.puts("   🔓 Worker #{id}: Liberando conexión")
                :ok
            end, timeout: @checkout_timeout_ms)
        rescue
            error ->
                IO.puts("   ❌ Worker #{id}: Error - #{inspect(error)}")
                {:error, error}
        catch
            :exit, {:timeout, _} ->
                IO.puts("   ⏰ Worker #{id}: Timeout esperando conexión")
                {:error, :timeout}
        end
    end

    defp simulate_bq_operation do
        try do
            result = Pool.BigQuery.with_connection(@pool_name, fn conn ->
                Connection.Odbc.query(conn, "SELECT 'operacion_completada' as status")
            end, timeout: @checkout_timeout_ms)

            {:ok, result}
        rescue
            error ->
                {:error, :exception, error}
        catch
            :exit, {:timeout, _} ->
                {:error, :timeout, "Pool timeout - no hay conexiones disponibles"}
        end
    end

    defp monitor_waiting_operation(start_time) do
        Enum.each(1..ceil(@hold_time_ms / 1000) + 3, fn _ ->
            Process.sleep(1_000)
            elapsed = System.monotonic_time(:millisecond) - start_time
            IO.puts("   ⏱️  Tiempo esperando: #{elapsed}ms")
        end)
    end

    defp show_pool_stats(label) do
        stats = Pool.BigQuery.pool_stats(@pool_name)
        IO.puts("\n📈 Pool Stats (#{label}):")
        IO.puts("   • Estado: #{inspect(stats[:state])}")
        IO.puts("   • Workers disponibles: #{stats[:available_workers]}")
        IO.puts("   • Workers overflow: #{stats[:overflow_workers]}")
        IO.puts("   • Checked out: #{stats[:checked_out]}")
    end

    defp show_results(result, elapsed_ms) do
        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 RESULTADOS")
        IO.puts(String.duplicate("-", 70))

        case result do
            {:ok, query_result} ->
                IO.puts("\n✅ Operación BigQuery: EXITOSA")
                IO.puts("   • Resultado: #{inspect(query_result)}")
                IO.puts("   • Tiempo total de espera: #{elapsed_ms}ms")

                if elapsed_ms >= @hold_time_ms do
                    IO.puts("\n🎯 COMPORTAMIENTO ESPERADO:")
                    IO.puts("   La operación tuvo que esperar ~#{@hold_time_ms}ms porque todas")
                    IO.puts("   las conexiones estaban siendo retenidas.")
                    IO.puts("   Una vez que una conexión se liberó, la operación se ejecutó.")
                else
                    IO.puts("\n⚠️  La operación se ejecutó antes de lo esperado.")
                    IO.puts("   Posiblemente hay max_overflow configurado o más conexiones.")
                end

            {:error, :timeout, message} ->
                IO.puts("\n⏰ Operación BigQuery: TIMEOUT")
                IO.puts("   • Mensaje: #{message}")
                IO.puts("   • Tiempo hasta timeout: #{elapsed_ms}ms")
                IO.puts("\n🎯 Esto indica que el pool está correctamente limitado")
                IO.puts("   y no hay conexiones disponibles (sin overflow).")

            {:error, :exception, error} ->
                IO.puts("\n❌ Operación BigQuery: ERROR")
                IO.puts("   • Error: #{inspect(error)}")
        end
    end
end

# Ejecutar el test
PoolTest.PoolBigQueryExhaustionTest.run()
