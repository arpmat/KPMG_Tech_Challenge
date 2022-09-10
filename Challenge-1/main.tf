
data "aws_availability_zones" "available" {}

resource "aws_vpc" "VPC-OPS" {
  cidr_block = "${var.vpc_cidr_block}"
  instance_tenancy = "default"

  tags = {
    Name = "${var.vpc_name}"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.default.id}"
  count             = "${length(var.web_subnets)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.public_cidr_blocks[count.index]}"

  tags = {
    Name = "web-tier-${count.index}"
  }

}

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.default.id}"
  count             = "${length(var.app_subnets)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.private_cidr_blocks[count.index]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "app-tier-${count.index}"
  }

}

resource "aws_subnet" "db" {
  count             = "${length(var.db_subnets)}"
  vpc_id            = "${aws_vpc.default.id}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.db_cidr_blocks[count.index]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "db-private-${count.index}"
  }

}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = "${aws_vpc.default.id}"

  tags = {
    Name = "${var.vpc_name}"
  }
}


resource "aws_route_table" "web" {
  vpc_id = "${aws_vpc.default.id}"

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
  vpc_id = "${aws_vpc.default.id}"

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
  vpc_id = "${aws_vpc.default.id}"

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


resource "aws_db_instance" "rds" {
  allocated_storage    = "${var.rds_storage}"
  engine               = "${var.rds_engine}"
  instance_class       = "${var.rds_instance_class}"
  name                 = "${var.rds_name}"
  username             = "${var.rds_username}"
  password             = "${var.rds_password}"
  db_subnet_group_name = "${var.rds_subnet_name}"
  depends_on = ["aws_db_subnet_group.rds_subnet_group"]
}

resource "aws_security_group" "web_sg" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.default.id}"

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

resource "aws_instance" "webservers" {
  count           = "${length(var.public_cidr_blocks)}"
  ami             = "${var.web_ami}"
  instance_type   = "${var.web_instance}"
  security_groups = ["${aws_security_group.webserver_sg.id}"]
  subnet_id       = "${element(aws_subnet.web.*.id,count.index)}"

  tags {
    Name = "${element(var.webserver_name,count.index)}"
  }
}

resource "aws_lb" "weblb" {
  name               = "${var.lb_name}"
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.webserver_sg.id}"]
  subnets            = ["${aws_subnet.web.*.id}"]

  tags {
    Name = "${var.lb_name}"
  }
}

resource "aws_lb_target_group" "alb_group" {
  name     = "${var.tg_name}"
  port     = "${var.tg_port}"
  protocol = "${var.tg_protocol}"
  vpc_id   = "${aws_vpc.default.id}"
}

resource "aws_lb_listener" "webserver-lb" {
  load_balancer_arn = "${aws_lb.weblb.arn}"
  port              = "${var.listener_port}"
  protocol          = "${var.listener_protocol}"

  default_action {
    target_group_arn = "${aws_lb_target_group.alb_group.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "allow_all" {
  listener_arn = "${aws_lb_listener.webserver-lb.arn}"

  action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.alb_group.arn}"
  }

  condition {
    field  = "path-pattern"
    values = ["*"]
  }
}
