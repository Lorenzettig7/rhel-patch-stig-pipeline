# Red Hat official AMIs (owner 309956199498), pay-as-you-go "Hourly2" GP3 images.

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.4*_HVM-*-x86_64-*-Hourly2-GP3"]
  }
}

data "aws_ami" "rhel8" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-8.8*_HVM-*-x86_64-*-Hourly2-GP3"]
  }
}
