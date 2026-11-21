output "instance_public_ips" {
  description = "Map of instance name to public IP."
  value       = { for name, inst in aws_instance.fleet : name => inst.public_ip }
}

output "evidence_bucket_name" {
  description = "Name of the S3 evidence bucket."
  value       = aws_s3_bucket.evidence.bucket
}
