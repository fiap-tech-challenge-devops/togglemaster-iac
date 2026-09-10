resource "aws_security_group" "demo_inseguro" {
  name        = "demo-inseguro"
  description = "Demo do gate de seguranca (remover)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH aberto para a internet (proposital)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}