
data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc_ops" {
  cidr_block = "${var.vpc_cidr_block}"
  instance_tenancy = "default"

  tags = {
    Name = "${var.vpc_name}"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.vpc_ops.id}"
  count             = "${length(var.web_subnets)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.public_cidr_blocks[count.index]}"

  tags = {
    Name = "web-tier-${count.index}"
	type = "public"
  }

}

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.vpc_ops.id}"
  count             = "${length(var.app_subnets)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.private_cidr_blocks[count.index]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "app-tier-${count.index}"
	type = "private"
  }

}

resource "aws_subnet" "db" {
  count             = "${length(var.db_subnets)}"
  vpc_id            = "${aws_vpc.vpc_ops.id}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.db_cidr_blocks[count.index]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "db-private-${count.index}"
	type = "database"
  }

}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = "${aws_vpc.vpc_ops.id}"

  tags = {
    Name = "${var.vpc_name}"
  }
}


resource "aws_route_table" "web" {
  vpc_id = "${aws_vpc.vpc_ops.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Name = "Public-route-table"
  }
}

resource "aws_eip" "nat_eip_p" {
  vpc = true

  tags = {
    Name = "Nat Gateway IP"
  }
}

resource "aws_eip" "nat_eip_s" {
  vpc = true

  tags = {
    Name = "Nat Gateway IP"
  }
}

resource "aws_nat_gateway" "web_1" {
  allocation_id = "${aws_eip.nat_eip_p.id}"
  subnet_id     = "${element(aws_subnet.public.*.id, 0)}"

}

resource "aws_nat_gateway" "web_2" {
  allocation_id = "${aws_eip.nat_eip_s.id}"
  subnet_id     = "${element(aws_subnet.public.*.id, 1)}"

}

resource "aws_route_table_association" "web_rts_p" {
  count          = "${length(var.public_cidr_blocks)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.web.id}"
}

resource "aws_route_table_association" "web_rts_s" {
  count          = "${length(var.public_cidr_blocks)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.web.id}"
}


resource "aws_route_table" "app" {
  vpc_id = "${aws_vpc.vpc_ops.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.default.id}"
  }

  tags {
    Name = "App"
  }
}

resource "aws_route_table_association" "app" {
  count          = "${length(var.private_cidr_blocks)}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${aws_route_table.app.id}"
}


resource "aws_route_table" "db" {
  vpc_id = "${aws_vpc.vpc_ops.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.default.id}"
  }

  tags {
    Name = "DB"
  }
}

resource "aws_route_table_association" "db" {
  count          = "${length(var.db_cidr_blocks)}"
  subnet_id      = "${element(aws_subnet.db.*.id, count.index)}"
  route_table_id = "${aws_route_table.db.id}"
}


resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.rds_subnet_name}"
  subnet_ids = ["${aws_subnet.db.*.id}"]

  tags {
    Name = "${var.rds_subnet_name}"
  }
}


resource "aws_security_group" "db-sg" {
    name = "rdsSG"
    description = "RDS security group"
    vpc_id = "${aws_vpc.vpc_ops.id}"  
    ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["${aws_subnet.private.cidr_block}"]
   }
   egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds" {
  allocated_storage    = "${var.rds_storage}"
  engine               = "${var.rds_engine}"
  instance_class       = "${var.rds_instance_class}"
  name                 = "${var.rds_name}"
  username             = "${var.rds_username}"
  password             = "${var.rds_password}"
  db_subnet_group_name = "${var.rds_subnet_name}"
  vpc_security_group_ids = ["${aws_security_group.db-sg.id}"]
  depends_on = ["aws_db_subnet_group.rds_subnet_group"]
}

resource "aws_security_group" "web_sg" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.vpc_ops.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.websg_name}"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.vpc_ops.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["$aws_security_group.internal_lb_sg.id"]
  }
  
  ingress {
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["$aws_subnet.db.id"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.websg_name}"
  }
}

resource "aws_security_group" "internal_lb_sg" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.vpc_ops.id}"

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["$aws_security_group.web_sg.id"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.websg_name}"
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = ${aws_vpc.vpc_ops.id}

  filter {
    name   = "tag:type"
	value  = "public"
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = ${aws_vpc.vpc_ops.id}

  filter {
    name   = "tag:type"
	value = "private"
  }
}

resource "aws_launch_configuration" "web_launch_conf" {
  name_prefix     = "web_auto_Scaling-"
  image_id        = "${var.web_ami}"
  instance_type   = "t2.micro"
  user_data       = file("user-data.sh")
  security_groups = "${aws_security_group.webserver_sg.id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "app_launch_conf" {
  name_prefix     = "app_auto_Scaling-"
  image_id        = "${var.app_ami}"
  instance_type   = "t2.micro"
  user_data       = file("app-data.sh")
  security_groups = "${aws_security_group.app_sg.id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.web_launch_conf.name
  vpc_zone_identifier  = ["${data.aws_subnet_ids.public.all.ids}"]
}


resource "aws_autoscaling_group" "app_asg" {
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  launch_configuration = "$aws_launch_configuration.app_launch_conf.name"
  vpc_zone_identifier  = ["${data.aws_subnet_ids.private.all.ids}"]
}

# Creating application load balancer



resource "aws_lb" "web_lb" {
  name               = "${var.lb_name}"
  load_balancer_type = "application"
  internal           = false
  enable_cross_zone_load_balancing = true
  security_groups    = ["${aws_security_group.webserver_sg.id}"]
  subnets            = ["${data.aws_subnet_ids.public.all.ids}"]

  tags {
    Name = "${var.lb_name}"
  }
}

resource "aws_autoscaling_attachment" "web_auto_att" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.id
  elb                    = aws_lb.web_lb.id
}

resource "aws_elb" "app_elb" {
  name               = "${var.lb_name}"
  load_balancer_type = "application"
  internal           = true
  enable_cross_zone_load_balancing = true
  security_groups    = ["${aws_security_group.internal_lb_sg.id}"]
  subnets            = ["${data.aws_subnet_ids.private.all.ids}"]
  
  listener {
     instance_port     = 8000
     instance_protocol = "http"
     lb_port           = 80
     lb_protocol       = "http"
   }

   listener {
     instance_port      = 8000
     instance_protocol  = "http"
     lb_port            = 443
     lb_protocol        = "https"
     ssl_certificate_id = "<arn>:server-certificate/certName"
   }

   health_check {
     healthy_threshold   = 2
     unhealthy_threshold = 2
     timeout             = 3
     target              = "HTTP:8000/"
     interval            = 30
   }

  tags {
    Name = "${var.lb_name}"
  }
}

resource "aws_autoscaling_attachment" "app_auto_att" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.id
  elb                    = aws_lb.app_lb.id
}
