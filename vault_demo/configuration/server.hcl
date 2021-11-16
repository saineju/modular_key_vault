ui = true
api_addr = "http://localhost:8200"
disable_mlock = true

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address = "localhost:8200"
  tls_disable = 1
}
