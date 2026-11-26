variable "cluster_name" {
  description = "Kind local"
  type        = string
  default     = "oficina-local"
}

variable "application_path" {
  description = "Caminho absoluto para o checkout de soat-fase1-tech-challenge; vazio usa a pasta irmã padrão."
  type        = string
  default     = ""
}

variable "api_host_port" {
  description = "Porta local para acessar a API publicada pelo cluster Kind."
  type        = number
  default     = 8081
}

variable "mailhog_host_port" {
  description = "Porta local para acessar o MailHog publicado pelo cluster Kind."
  type        = number
  default     = 8025
}
