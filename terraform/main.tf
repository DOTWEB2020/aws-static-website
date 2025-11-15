# main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Create S3 bucket for our website
resource "aws_s3_bucket" "my_portfolio_bucket" {
  bucket = var.bucket_name
  
  tags = {
    Name        = "My Portfolio Website"
    Project     = "AWS Static Website"
    Environment = "production"
  }
}

# Configure the S3 bucket as a website
resource "aws_s3_bucket_website_configuration" "my_website" {
  bucket = aws_s3_bucket.my_portfolio_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Make the bucket publicly readable
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.my_portfolio_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Set bucket policy to allow public read access
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.my_portfolio_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.my_portfolio_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

# Create CloudFront Distribution (CDN) - SIMPLIFIED VERSION
resource "aws_cloudfront_distribution" "website_cdn" {
  origin {
    domain_name = aws_s3_bucket.my_portfolio_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "My portfolio website CDN"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"  # Use only North America and Europe to save costs

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use CloudFront default certificate (no custom domain needed)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "portfolio-website-cdn"
  }
}

# Upload our website files to S3
resource "aws_s3_object" "website_files" {
  for_each = fileset("${path.module}/website/", "**/*.*")

  bucket       = aws_s3_bucket.my_portfolio_bucket.id
  key          = each.value
  source       = "${path.module}/website/${each.value}"
  etag         = filemd5("${path.module}/website/${each.value}")
  content_type = lookup(var.content_types, regex("\\.[^.]+$", each.value), "binary/octet-stream")
}

# Output the website URLs
output "website_url" {
  description = "S3 Website URL"
  value       = "http://${aws_s3_bucket.my_portfolio_bucket.bucket}.s3-website-${var.region}.amazonaws.com"
}

output "cloudfront_url" {
  description = "CloudFront Distribution URL"
  value       = "https://${aws_cloudfront_distribution.website_cdn.domain_name}"
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.my_portfolio_bucket.bucket
}