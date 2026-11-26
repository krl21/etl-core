ExUnit.start()

Mox.defmock(Connection.OdbcMock, for: Connection.Odbc.Behaviour)
Mox.defmock(Connection.PostgresMock, for: Connection.Postgres.Behaviour)
Mox.defmock(Connection.PostgresPoolMock, for: Connection.PostgresPool.Behaviour)
Mox.defmock(Connection.HttpMock, for: Connection.Http.Behaviour)
Mox.defmock(Genserver.AmqpMock, for: Genserver.Amqp.Behaviour)

Application.put_env(:etl_core, :deps,
  odbc: Connection.OdbcMock,
  postgres: Connection.PostgresMock,
  postgres_pool: Connection.PostgresPoolMock,
  http: Connection.HttpMock,
  amqp: Genserver.AmqpMock
)
