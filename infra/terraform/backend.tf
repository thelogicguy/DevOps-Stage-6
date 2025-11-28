terraform {
  backend "s3" {
    bucket         = "todo-terraform-state-bucket-12345"
    key            = "todo-app/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}