terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.1.0"
    }
  }
}

provider "scaleway" {
  access_key = "SCW3FCFX7MQM1GA3VFM3"
  secret_key = "a23e3b80-d579-42ed-822d-73011e7eb5ac"
  project_id = "2c1abec4-43a9-4123-9708-11ef95bbfa9c"
}

resource "scaleway_rdb_instance" "database" {
  name           = "test-database-devops"
  node_type      = "db-dev-s"
  engine         = "PostgreSQL-12"
  is_ha_cluster  = false
  disable_backup = true
  user_name      = "my_root_user"
  password       = "My_r00t_p4sSw0rD"
}

resource "scaleway_instance_ip" "server_ip" {
  count = 2
}

resource "scaleway_lb_ip" "ip" {
}

resource "scaleway_instance_security_group" "web" {
  inbound_default_policy = "drop"

  inbound_rule {
    action = "accept"
    port   = 80
    ip     = scaleway_lb.base_lb.ip_address
  }
}

resource "scaleway_instance_server" "servers" {
  count = 2
  type  = "DEV1-S"
  image = "ubuntu_focal"
  ip_id = scaleway_instance_ip.server_ip[count.index].id
  name  = "test-node-server-devops"
  //security_group_id = scaleway_instance_security_group.web.id
  user_data = {
    DATABASE_URI = "postgres://${scaleway_rdb_instance.database.user_name}:${scaleway_rdb_instance.database.password}@${scaleway_rdb_instance.database.endpoint_ip}:${scaleway_rdb_instance.database.endpoint_port}/rdb"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get remove docker docker-engine docker.io containerd runc",
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "sudo gpasswd -a $USER docker",
      "sudo service docker restart",
      "docker run -d --name app -e DATABASE_URI=\"$(scw-userdata DATABASE_URI)\" -p 80:8080 --restart=always rg.fr-par.scw.cloud/efrei-devops/app:latest",
    ]
    connection {
      host        = self.public_ip
      type        = "ssh"
      user        = "root"
      private_key = file(pathexpand("~/.ssh/id_rsa"))
    }
  }
}

resource "scaleway_lb" "base_lb" {
  ip_id = scaleway_lb_ip.ip.id
  zone  = "fr-par-1"
  type  = "LB-S"
}

resource "scaleway_lb_certificate" "certificate" {
  lb_id = scaleway_lb.base_lb.id
  letsencrypt {
    common_name = "51.159.27.87.sslip.io"
  }
}

resource "scaleway_lb_backend" "backend01" {
  lb_id            = scaleway_lb.base_lb.id
  name             = "backend01"
  forward_protocol = "http"
  forward_port     = "80"
  server_ips       = [for o in scaleway_instance_server.servers : o.private_ip]
}

resource "scaleway_lb_frontend" "frontend01" {
  lb_id          = scaleway_lb.base_lb.id
  backend_id     = scaleway_lb_backend.backend01.id
  name           = "frontend01"
  inbound_port   = "443"
  certificate_id = scaleway_lb_certificate.certificate.id
}
