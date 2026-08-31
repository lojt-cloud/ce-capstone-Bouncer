# ADR 0005: Pinned AMI ID via SSM lookup, not a Packer golden image

## Status
Accepted

## Context
The locked architecture decision allows either a pinned AMI ID or a
Packer-built golden image, as long as it's not a "most recent" dynamic
lookup at apply time. No Packer experience on this project, and the app's
boot-time setup (pip install of Flask/Gunicorn, CloudWatch agent config)
is fast enough on a t3.micro that a golden image's main benefit --
avoiding repeated package installs -- wasn't worth the added tooling.

## Decision
Looked up the current standard AL2023 AMI once via the AWS-published SSM
parameter (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64`),
then hardcoded the resulting AMI ID as a Terraform variable default. This
is a one-time manual lookup, not a live `data "aws_ami"` source, so
re-applies stay reproducible.

## Consequences
- Simpler than standing up a Packer pipeline for a capstone-scale project.
- Boot time is a few minutes (dnf update + pip install) rather than
  near-instant; acceptable given the ASG's 300s health check grace period.
- The AMI needs a manual re-lookup and re-pin if AL2023 needs updating --
  no auto-drift, but also no auto-patching.