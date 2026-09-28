return {
  protocol = "ccfleet.v2",
  controller_id = 0,
  server_url = "https://SEU-ENDERECO.ngrok-free.app",
  fleet_token = "123",
  turtle_name = "worker-01",
  gps_timeout = 5,

  -- Atualizacao da telemetria.
  status_interval = 1,

  -- Durante construcoes a turtle pode quebrar blocos que bloqueiam o caminho.
  build_dig_obstacles = true,
}
