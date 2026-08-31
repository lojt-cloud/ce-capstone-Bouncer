# Incident 0004: AMI lookup filter matched the wrong image variant

## Summary
A `describe-images` filter intended to find the current AL2023 AMI
matched an ECS+Neuron (Inferentia/Trainium-optimized) variant instead of
the plain base image.

## Root cause
Filter used was `Name=name,Values=al2023-ami-*-x86_64`, sorted by
CreationDate, taking the most recent match. AL2023 ships several name
variants under that same wildcard -- standard, minimal, ecs, ecs-neuron,
eks -- and the ECS+Neuron variant happened to have the most recent
publish date at lookup time, so the wildcard silently picked it over the
standard image.

## Fix
Switched to the AWS-published SSM parameter
(`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64`),
which always resolves to exactly the standard AL2023 image for the given
kernel, with no wildcard ambiguity.

## Lesson
A wildcard `describe-images` filter across an AMI family that has
several specialized variants under a similar name pattern isn't safe to
sort-by-date-and-take-latest -- the "latest" match isn't necessarily the
"standard" one. The SSM public parameter path is the more reliable
source for this kind of lookup.