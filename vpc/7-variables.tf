variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

}

variable "azs" {
  description = "Availability Zones for subnets"
  type        = list(string)

}
variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)

}

variable "private_subnet_tags" {
  description = "Private subnets tags"
  type        = map(any)

}

variable "public_subnet_tags" {
  description = "Public subnets tags"
  type        = map(any)

}
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}