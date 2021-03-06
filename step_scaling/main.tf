////////////////////////////////////////////////////////////////////////////////
// AWS

provider "aws" {
  region = "ap-northeast-1"
}

////////////////////////////////////////////////////////////////////////////////
// Variable

variable "key_name" {}

////////////////////////////////////////////////////////////////////////////////
// VPC

locals {
  availability_zones = [
    "ap-northeast-1a",
    "ap-northeast-1c",
  ]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_security_group" "default" {
  name = "default"
}

////////////////////////////////////////////////////////////////////////////////
// AutoScaling

data "aws_ami" "app" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_launch_template" "app" {
  name                   = "hello-asg-app"
  image_id               = "${data.aws_ami.app.id}"
  instance_type          = "t2.nano"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${data.aws_security_group.default.id}"]

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name = "hello-asg-app-${aws_launch_template.app.latest_version}"

  launch_template = {
    id      = "${aws_launch_template.app.id}"
    version = "${aws_launch_template.app.latest_version}"
  }

  min_size = 1
  max_size = 4

  vpc_zone_identifier = ["${data.aws_subnet_ids.default.ids}"]

  tag {
    key                 = "Name"
    value               = "hello-asg-app"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  autoscaling_group_name    = "${aws_autoscaling_group.app.name}"
  name                      = "cpu"
  policy_type               = "StepScaling"
  adjustment_type           = "ExactCapacity"
  estimated_instance_warmup = 60
  metric_aggregation_type   = "Sum"

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 40
  }

  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 40
    metric_interval_upper_bound = 80
  }

  step_adjustment {
    scaling_adjustment          = 3
    metric_interval_lower_bound = 80
    metric_interval_upper_bound = 120
  }

  step_adjustment {
    scaling_adjustment          = 4
    metric_interval_lower_bound = 120
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name  = "cpu"
  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Sum"
  period      = "60"

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "3"

  alarm_actions = ["${aws_autoscaling_policy.cpu.arn}"]
}
