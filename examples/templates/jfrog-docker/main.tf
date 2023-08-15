terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.11.1"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
    artifactory = {
      source  = "registry.terraform.io/jfrog/artifactory"
      version = "~> 8.4.0"
    }
  }
}

locals {
  # if the jfrog username is same as the coder username, you can use the following
  # artifactory_username = data.coder_workspace.me.owner
  # if the username is same as email, you can use the following
  # artifactory_username = urlencode(data.coder_workspace.me.owner_email)
  artifactory_username = data.coder_workspace.me.owner
  artifactory_repository_keys = {
    "npm"    = "npm"
    "python" = "python"
    "go"     = "go"
  }
  workspace_user = data.coder_workspace.me.owner
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

variable "jfrog_host" {
  type        = string
  description = "JFrog instance hostname. For example, 'YYY.jfrog.io'."
}

variable "artifactory_access_token" {
  type        = string
  description = "The admin-level access token to use for JFrog."
}

# Configure the Artifactory provider
provider "artifactory" {
  url          = "https://${var.jfrog_host}/artifactory"
  access_token = var.artifactory_access_token
}

resource "artifactory_scoped_token" "me" {
  username = local.artifactory_username
}

resource "coder_agent" "main" {
  arch                   = data.coder_provisioner.me.arch
  os                     = "linux"
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    # The jf CLI checks $CI when determining whether to use interactive
    # flows.
    export CI=true

    jf c rm 0 || true
    echo ${artifactory_scoped_token.me.access_token} | \
      jf c add --access-token-stdin --url https://${var.jfrog_host} 0

    # Configure the `npm` CLI to use the Artifactory "npm" repository.
    cat << EOF > ~/.npmrc
    email = ${data.coder_workspace.me.owner_email}
    registry = https://${var.jfrog_host}/artifactory/api/npm/${local.artifactory_repository_keys["npm"]}
    EOF
    jf rt curl /api/npm/auth >> .npmrc

    # Configure the `pip` to use the Artifactory "python" repository.
    mkdir -p ~/.pip
    cat << EOF > ~/.pip/pip.conf
    [global]
    index-url = https://${local.artifactory_username}:${artifactory_scoped_token.me.access_token}@${var.jfrog_host}/artifactory/api/pypi/${local.artifactory_repository_keys["python"]}/simple
    EOF

  EOT
  # Set GOPROXY to use the Artifactory "go" repository.
  env = {
    GOPROXY : "https://${local.artifactory_username}:${artifactory_scoped_token.me.access_token}@${var.jfrog_host}/artifactory/api/go/${local.artifactory_repository_keys["go"]}"
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${local.workspace_user}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.workspace_user
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname   = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.workspace_user}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
}
