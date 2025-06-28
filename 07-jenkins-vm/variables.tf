variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
}
variable "gcp_project_id_prefix" {
  description = "A short prefix for naming resources."
  type        = string
}
variable "environment" {
  description = "The deployment environment (e.g., 'dev', 'prod')."
  type        = string
}
variable "zone" {
  description = "The GCP zone for the Jenkins VM."
  type        = string
}
variable "machine_type" {
  description = "The machine type for the Jenkins VM."
  type        = string
  default     = "e2-medium"
}
variable "subnet_self_link" {
  description = "The self_link of the subnet to attach the Jenkins VM to."
  type        = string
}
variable "jenkins_service_account_email" {
  description = "The email of the service account for the Jenkins VM."
  type        = string
}

variable "tags" {
  description = "A map of tags to add to the VM."
  type        = map(string)
  default     = {}
}

variable "vpc_self_link" {
  description = "The self_link of the VPC network where the firewall rules will be created."
  type        = string
}

variable "jenkins_http_source_ranges" {
  description = "List of CIDR IP ranges which can have http access to my bastion server "
  type = list(string)
  default = [ ]
  
}

variable "jenkins_ssh_source_ranges" {
  description = "List of CIDR IP ranges which can have SSH access to my Jenkins-master server "
  type = list(string)
  default = [ ]
  
}