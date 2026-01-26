
defmodule PoolTest.PoolExhaustionTest do
    @moduledoc """
    Test para verificar el comportamiento del pool de conexiones PostgreSQL cuando todas las conexiones están siendo utilizadas.

    Este test:
    1. Crea un pool pequeño (3 conexiones)
    2. Toma TODAS las conexiones disponibles con transacciones que retienen
    3. Intenta ejecutar una query adicional (simulando procesar un expediente)
    4. Verifica que la query tiene que esperar hasta que una conexión esté disponible

    ## Uso

    Ejecutar desde la raíz del proyecto:

        mix run pool-test/pool_exhaustion_test.exs

    ## Requisitos

    - PostgreSQL corriendo y accesible
    - Variables de entorno configuradas:
        - PG_HOST
        - PG_PORT
        - PG_DATABASE
        - PG_USERNAME
        - PG_PASSWORD
    """

    require Logger

    @pool_name :test_exhaustion_pool
    @pool_size 5                # Número de conexiones a saturar
    @total_concurrent_queries 30
    @hold_time_ms 2_000          # Tiempo que cada conexión se retiene
    @queue_timeout_ms 15_000     # Timeout para queries en cola (mayor que hold_time)

    def run do
        Logger.configure(level: :info)
        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🧪 TEST: Pool Exhaustion - Verificar comportamiento con pool saturado")
        IO.puts(String.duplicate("=", 70))

        config = get_pg_config()

        IO.puts("\n📋 Configuración del test:")
        IO.puts("   • Pool size: #{@pool_size} conexiones")
        IO.puts("   • Tiempo de retención por conexión: #{@hold_time_ms}ms")
        IO.puts("   • Timeout para queries en cola: #{@queue_timeout_ms}ms")
        IO.puts("   • Host: #{config[:hostname]}:#{config[:port]}")
        IO.puts("   • Database: #{config[:database]}")

        # Iniciar el pool de prueba
        case start_test_pool(config) do
        {:ok, _pid} ->
            IO.puts("\n✅ Pool de prueba iniciado correctamente")
            run_exhaustion_test()

        {:error, reason} ->
            IO.puts("\n❌ Error iniciando pool: #{inspect(reason)}")
            System.halt(1)
        end
    end

    defp get_pg_config do
        %{
            hostname: System.get_env("PG_HOST"),
            port: String.to_integer(System.get_env("PG_PORT")),
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

    defp run_exhaustion_test do
        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 1: Verificar que el pool funciona normalmente")
        IO.puts(String.duplicate("-", 70))

        case Pool.Postgres.query(@pool_name, "SELECT 1", []) do
        {:ok, result} ->
            IO.puts("✅ Query de prueba exitosa: #{inspect(result.rows)}")

        {:error, reason} ->
            IO.puts("❌ Error en query de prueba: #{inspect(reason)}")
            System.halt(1)
        end

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 2: Saturar el pool - Tomar TODAS las conexiones")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n🔒 Iniciando #{@total_concurrent_queries} transacciones que retendrán las conexiones...")

        # Crear tareas que toman todas las conexiones y las retienen
        holder_tasks = for i <- 1..@total_concurrent_queries do
            Task.async(fn ->
                connection_holder(i)
            end)
        end

        # Esperar un momento para asegurar que las transacciones iniciaron
        Process.sleep(500)

        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 FASE 3: Intentar procesar un expediente (query adicional)")
        IO.puts(String.duplicate("-", 70))

        IO.puts("\n⏳ Intentando ejecutar query con pool saturado...")
        IO.puts("   (Debería esperar hasta que una conexión se libere)\n")

        # Medir el tiempo que tarda en ejecutarse la query
        start_time = System.monotonic_time(:millisecond)

        # Intentar ejecutar una query adicional (simula procesar expediente)
        expediente_task = Task.async(fn ->
            simulate_expediente_processing()
        end)

        # Mientras esperamos, mostrar progreso
        monitor_task = Task.async(fn ->
        monitor_waiting_query(start_time)
        end)

        # Esperar a que todas las tareas terminen
        Task.await(monitor_task, @hold_time_ms + 10_000)

        expediente_result = Task.await(expediente_task, @queue_timeout_ms + 10_000)
        end_time = System.monotonic_time(:millisecond)

        # Esperar a que las tareas de retención terminen
        Enum.each(holder_tasks, fn task ->
            Task.await(task, @hold_time_ms + 10_000)
        end)

        # Mostrar resultados
        show_results(expediente_result, end_time - start_time)

        # Limpiar
        Supervisor.stop(__MODULE__.Supervisor)

        IO.puts("\n" <> String.duplicate("=", 70))
        IO.puts("🏁 Test completado")
        IO.puts(String.duplicate("=", 70) <> "\n")
    end

    defp connection_holder(id) do
        IO.puts("   🔐 Conexión #{id}: Iniciando transacción...")

        Pool.Postgres.transaction(@pool_name, fn conn ->
            Postgrex.query!(conn, "SELECT pg_sleep(0.1)", [])  # Query inicial
            IO.puts("   🔐 Conexión #{id}: ✅ Transacción activa, reteniendo por #{@hold_time_ms}ms")

            # Retener la conexión
            Process.sleep(@hold_time_ms)

            IO.puts("   🔓 Conexión #{id}: Liberando transacción")
            :ok
        end)
    end

    defp simulate_expediente_processing do
        # Simular el procesamiento de un expediente que requiere una conexión
        case Pool.Postgres.query(@pool_name, "SELECT 'expediente_procesado' as status, now() as timestamp", [], timeout: @queue_timeout_ms) do
        {:ok, result} ->
            {:ok, result}

        {:error, %DBConnection.ConnectionError{message: message}} ->
            {:error, :timeout, message}

        {:error, reason} ->
            {:error, :other, reason}
        end
    end

    defp monitor_waiting_query(start_time) do
        # Mostrar cada segundo cuánto tiempo lleva esperando
        Enum.each(1..ceil(@hold_time_ms / 1000) + 5, fn _ ->
            Process.sleep(1_000)
            elapsed = System.monotonic_time(:millisecond) - start_time
            IO.puts("   ⏱️  Tiempo esperando: #{elapsed}ms")
        end)
    end

    defp show_results(result, elapsed_ms) do
        IO.puts("\n" <> String.duplicate("-", 70))
        IO.puts("📊 RESULTADOS")
        IO.puts(String.duplicate("-", 70))

        case result do
        {:ok, query_result} ->
            IO.puts("\n✅ Query del expediente: EXITOSA")
            IO.puts("   • Resultado: #{inspect(query_result.rows)}")
            IO.puts("   • Tiempo total de espera: #{elapsed_ms}ms")

            if elapsed_ms >= @hold_time_ms do
            IO.puts("\n🎯 COMPORTAMIENTO ESPERADO:")
            IO.puts("   La query tuvo que esperar ~#{@hold_time_ms}ms porque todas")
            IO.puts("   las conexiones estaban siendo retenidas por las transacciones.")
            IO.puts("   Una vez que una conexión se liberó, la query se ejecutó.")
            else
            IO.puts("\n⚠️  La query se ejecutó antes de lo esperado.")
            IO.puts("   Posiblemente el pool tiene más conexiones o hay overflow.")
            end

        {:error, :timeout, message} ->
            IO.puts("\n⏰ Query del expediente: TIMEOUT")
            IO.puts("   • Mensaje: #{message}")
            IO.puts("   • Tiempo hasta timeout: #{elapsed_ms}ms")
            IO.puts("\n🎯 Esto indica que el pool está correctamente limitado")
            IO.puts("   y no hay conexiones disponibles (sin overflow).")

        {:error, :other, reason} ->
            IO.puts("\n❌ Query del expediente: ERROR")
            IO.puts("   • Razón: #{inspect(reason)}")
        end
    end
end

# Ejecutar el test
PoolTest.PoolExhaustionTest.run()
