# 1. PROVIDER: AWS ile konuşacağımızı belirtiyoruz.
provider "aws" {
  region = "us-east-1"
}

# 2. RESOURCE: S3 Bucket (Depolama Kovası)
# Neden "random" bir isim lazım?
# Çünkü S3 bucket isimleri "Dünya Çapında" benzersiz olmalıdır.
# "oytun-cv" ismini başkası aldıysa sen alamazsın.
# O yüzden ismin sonuna rastgele sayılar eklemek veya çok spesifik bir isim bulmak gerekir.

resource "aws_s3_bucket" "cv_bucket" {
  bucket = "oytun-bulut-cv-2025-v1"  # <-- BURAYI KENDİNE GÖRE DEĞİŞTİR (Benzersiz olsun)

  tags = {
    Name        = "Oytun CV Sitesi"
    Environment = "DevSecOps-Challenge"
  }
}

# 3. GÜVENLİK AYARI: Sahiplik Kontrolü
# Bu ayar, bucket'ın sahibinin (senin) tam yetkili olmasını sağlar.
resource "aws_s3_bucket_ownership_controls" "sahiplik" {
  bucket = aws_s3_bucket.cv_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
# --- BÖLÜM 2: CLOUDFRONT (GÜVENLİ DAĞITICI) ---

# 4. KİMLİK KARTI (Origin Access Control)
# CloudFront'un S3'e "Ben yetkiliyim" demesini sağlayan kart.
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "Oytun-CV-Erisim-Karti"
  description                       = "S3 Kova Erisimi Icin Guvenlik Karti"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 5. DAĞITIM (CloudFront Distribution)
# Sitemizi dünyaya sunan sistem.
resource "aws_cloudfront_distribution" "s3_distribution" {
  
  # Hangi Kovayı Sunacağız?
  origin {
    domain_name              = aws_s3_bucket.cv_bucket.bucket_regional_domain_name
    origin_id                = "S3-Oytun-CV"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  default_root_object = "index.html" # Siteye girenler direkt CV'yi görsün

  # Önbellek ve Davranış Ayarları
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"] # Sadece okumaya izin ver (Hacklenemez)
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Oytun-CV"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https" # HTTP girenleri HTTPS'e zorla (Güvenlik!)
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Coğrafi Kısıtlama (Şimdilik herkese açık)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL Sertifikası (AWS'nin ücretsiz sertifikası)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# 6. S3 KAPI KURALI (Bucket Policy)
# S3'e diyoruz ki: "Sadece bu CloudFront dağıtımına izin ver, gerisini reddet."
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.cv_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject" # Sadece dosya okuma izni
        Resource  = "${aws_s3_bucket.cv_bucket.arn}/*" # Kovanın içindeki her şey
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}

# 7. ÇIKTI (Output)
# İşlem bitince site adresini ekrana yazdıralım.
output "site_adresi" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
# --- BÖLÜM 3: SERVERLESS BACKEND ---

# 8. VERİTABANI (DynamoDB)
resource "aws_dynamodb_table" "counter_table" {
  name           = "ZiyaretciSayaci"
  billing_mode   = "PAY_PER_REQUEST" # Kullandıkça öde (Bedava sürümde kalır)
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S" # String (Metin)
  }
}

# 9. KOD PAKETLEME
# Python dosyasını AWS'ye yüklemek için .zip yapmamız lazım.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# 10. IAM ROLÜ (Kimlik)
# Lambda'nın AWS servislerine erişmesi için bir kimliğe ihtiyacı var.
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 11. YETKİ TANIMLAMA (Policy)
# Lambda'ya "Veritabanına yazabilirsin" izni veriyoruz.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_dynamodb_policy"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.counter_table.arn
      }
    ]
  })
}

# 12. LAMBDA FONKSİYONU (Beyin)
resource "aws_lambda_function" "visitor_counter" {
  filename      = "lambda_function.zip"
  function_name = "ZiyaretciSayaciFonksiyonu"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# 13. FUNCTION URL (Halka Açık Link)
# Bu fonksiyonu internetten tetiklemek için bir link oluşturuyoruz.
# API Gateway yerine bu daha basit ve ucuzdur.
resource "aws_lambda_function_url" "test_live" {
  function_name      = aws_lambda_function.visitor_counter.function_name
  authorization_type = "NONE" # Herkes tetikleyebilir

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["GET"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

# 14. ÇIKTI: Fonksiyonun Linki
output "api_adresi" {
  value = aws_lambda_function_url.test_live.function_url
}