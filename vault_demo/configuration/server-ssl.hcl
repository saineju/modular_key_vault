ui = true
api_addr = "https://localhost:8200"

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/localhost.pem"
  tls_key_file = "/vault/certs/localhost.key"
  tls_disable_client_certs = true
}
