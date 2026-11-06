-- platform: host-agnostic -- the configuration build/check-release-on-10.9.sh gives its mux servers and CLI
-- spec: INGREDIENTS.md "On-target acceptance" -- with WEZTERM_CHECK_TLS_SERVER a mux server also
--       listens with TLS on that address; with WEZTERM_CHECK_TLS_CLIENT (a port) it has three TLS
--       client domains for that port: "tls", which should connect, and "tls-untrusted" (another CA)
--       and "tls-wrong-host" (a name the server's certificate does not carry), which should not.
--       With WEZTERM_CHECK_SSH_PORT it has SSH domains for the check's sshd on 127.0.0.1 at that
--       port, without a remote mux, three for each backend B (libssh and ssh2): "ssh-B", which
--       should connect, and "ssh-B-wrong-host" (a known_hosts with another host key) and
--       "ssh-B-unauthorized" (a client key sshd does not authorize), which should not.
local config = { check_for_updates = false }
local dir = os.getenv('WEZTERM_CHECK_TLS_DIR')
local server = os.getenv('WEZTERM_CHECK_TLS_SERVER')
local port = os.getenv('WEZTERM_CHECK_TLS_CLIENT')
if server then
  config.tls_servers = { {
    bind_address = server,
    pem_cert = dir .. '/server.pem',
    pem_private_key = dir .. '/server.key',
    pem_root_certs = { dir .. '/ca.pem' },
  } }
end
local function client(name, host, ca)
  return {
    name = name,
    remote_address = host .. ':' .. port,
    pem_cert = dir .. '/client.pem',
    pem_private_key = dir .. '/client.key',
    pem_root_certs = { dir .. '/' .. ca },
  }
end
if port then
  config.tls_clients = {
    client('tls', 'localhost', 'ca.pem'),
    client('tls-untrusted', 'localhost', 'other-ca.pem'),
    client('tls-wrong-host', '127.0.0.1', 'ca.pem'),
  }
end
local ssh_dir = os.getenv('WEZTERM_CHECK_SSH_DIR')
local ssh_port = os.getenv('WEZTERM_CHECK_SSH_PORT')
-- spec: INGREDIENTS.md "On-target acceptance" -- only the check's own key and known_hosts: no agent,
--       and nothing from ~/.ssh
local function ssh(name, backend, key, known_hosts)
  return {
    name = name,
    remote_address = '127.0.0.1:' .. ssh_port,
    username = os.getenv('USER'),
    multiplexing = 'None',
    ssh_backend = backend,
    no_agent_auth = true,
    ssh_option = {
      identityfile = ssh_dir .. '/' .. key,
      userknownhostsfile = ssh_dir .. '/' .. known_hosts,
    },
  }
end
if ssh_port then
  config.ssh_domains = {}
  for _, b in ipairs({ { 'libssh', 'LibSsh' }, { 'ssh2', 'Ssh2' } }) do
    table.insert(config.ssh_domains, ssh('ssh-' .. b[1], b[2], 'client', 'known_hosts'))
    table.insert(config.ssh_domains, ssh('ssh-' .. b[1] .. '-wrong-host', b[2], 'client', 'other_known_hosts'))
    table.insert(config.ssh_domains, ssh('ssh-' .. b[1] .. '-unauthorized', b[2], 'other-client', 'known_hosts'))
  end
end
return config
