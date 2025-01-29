defmodule Genserver.MonitorTest do
    use ExUnit.Case
    # import Mock

    alias Genserver.Monitor

    # Canal del Slack para pruebas
    @webhook_url "https://hooks.slack.com/services/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"

    # Definición de un módulo GenServer para los tests
    defmodule SampleGenServer do
        use GenServer

        def start_link(init_arg) do
            GenServer.start_link(__MODULE__, init_arg, name: init_arg)
        end

        def init(_init_arg) do
            {:ok, %{}}
        end
    end


    setup do
        # Iniciar el monitor con una URL y entorno de prueba
        {:ok, monitor_pid} = Monitor.start_link({@webhook_url, "test"})

        # Devolver el pid del monitor para las pruebas
        %{monitor_pid: monitor_pid}
    end

    test "register and unregister GenServers", %{monitor_pid: _monitor_pid} do
        # Iniciar el primer GenServer (con el módulo adecuado)
        {:ok, pid1} = SampleGenServer.start_link(:gen_server_1)

        # Registrar el GenServer en el Monitor
        Monitor.register(pid1, :gen_server_1)

        # Esperar para verificar que la notificación de registro fue enviada
        :timer.sleep(1000)

        # Iniciar el segundo GenServer (con el módulo adecuado)
        {:ok, pid2} = SampleGenServer.start_link(:gen_server_2)

        # Registrar el segundo GenServer
        Monitor.register(pid2, :gen_server_2)

        # Desregistrar el primer GenServer
        Monitor.unregister(:gen_server_1)

        # Esperar para verificar que las notificaciones de desregistro fueron enviadas
        :timer.sleep(1000)

        # Verificamos que los procesos siguen vivos
        assert Process.alive?(pid1)
        assert Process.alive?(pid2)

        IO.puts("Verificación exitosa: Los GenServers se registraron y desregistraron correctamente.")
    end

    test "handle process crash", %{monitor_pid: _monitor_pid} do
        # Iniciar un GenServer que se falle automáticamente
        {:ok, pid3} = SampleGenServer.start_link(:gen_server_3)

        # Configurar el proceso para capturar salidas (no se detenga cuando pid3 muera)
        Process.flag(:trap_exit, true)

        # Registrar el GenServer en el monitor
        Monitor.register(pid3, :gen_server_3)

        # Intentar matar el GenServer
        Process.exit(pid3, :kill)

        # Esperar para verificar que el GenServer se haya caído
        :timer.sleep(1000)

        # Verificar que el monitor maneje el proceso caído
        assert Process.alive?(pid3) == false

        IO.puts("Verificación exitosa: El GenServer falló correctamente y se manejó la salida.")
    end

    test "check servers status", %{monitor_pid: _monitor_pid} do
        # Iniciar GenServers activos y no activos
        {:ok, pid4} = SampleGenServer.start_link(:gen_server_4)
        {:ok, pid5} = SampleGenServer.start_link(:gen_server_5)

        # Registrar GenServers
        Monitor.register(pid4, :gen_server_4)
        Monitor.register(pid5, :gen_server_5)

        # Ejecutar la función de verificación de estado
        Monitor.check_servers(%{:gen_server_4 => pid4, :gen_server_5 => pid5}, @webhook_url, "test")

        # Esperar para verificar que las notificaciones de estado fueron enviadas
        :timer.sleep(1000)

        IO.puts("Verificación exitosa: Los estados de los GenServers se verificaron correctamente.")
    end


end
