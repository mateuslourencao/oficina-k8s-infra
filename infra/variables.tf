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
