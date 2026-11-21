provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "lm-demo"
      ManagedBy = "terraform"
    }
  }
}
