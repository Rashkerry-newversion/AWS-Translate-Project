provider "aws" {
  region = "us-east-1"
}

# --------------------------
# 1. S3 BUCKETS
# --------------------------

resource "aws_s3_bucket" "input_bucket" {
  bucket = "whisper-scrolls-lingobotic"
  force_destroy = true
}

resource "aws_s3_bucket" "output_bucket" {
  bucket = "echo-reverie-lingobotic"
  force_destroy = true
}

# Lifecycle for input bucket
resource "aws_s3_bucket_lifecycle_configuration" "input_lifecycle" {
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    id     = "expire-inputs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }
  }
}

# Lifecycle for output bucket
resource "aws_s3_bucket_lifecycle_configuration" "output_lifecycle" {
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    id     = "expire-outputs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 60
    }
  }
}

# --------------------------
# 2. IAM FOR LAMBDA
# --------------------------

resource "aws_iam_role" "lambda_exec" {
  name = "lingobotic-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lingobotic-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "translate:TranslateText"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.input_bucket.arn}/*",
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# --------------------------
# 3. LAMBDA FUNCTION
# --------------------------

resource "aws_lambda_function" "translate_func" {
  function_name = "lingobotic-translator"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.lambda_handler"
  filename      = "lambda_function.zip"
  timeout       = 30

  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      TARGET_BUCKET_NAME = aws_s3_bucket.output_bucket.bucket
    }
  }
}

# --------------------------
# 4. S3 TRIGGER SETUP
# --------------------------

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translate_func.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

resource "aws_s3_bucket_notification" "s3_trigger" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.translate_func.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
