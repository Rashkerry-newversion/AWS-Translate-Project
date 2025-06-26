# main.tf
# This Terraform configuration provisions the necessary AWS resources for the
# automated text processing pipeline.

# Specify the AWS provider and region
provider "aws" {
  region = "us-east-1" # You can change this to your preferred AWS region
}

# -----------------------------------------------------------------------------
# 1. S3 Buckets
# -----------------------------------------------------------------------------

# S3 Bucket for Input Files - now with a fun, unique name!
resource "aws_s3_bucket" "input_files_bucket" {
  bucket = "whisper-scrolls-${var.bucket_name_suffix}" # Fun: where the input secrets (text) are placed
  #acl    = "private" # Restrict public access by default

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "DataIngestion" # More generic purpose
  }
}

# S3 Bucket Lifecycle Configuration for Input Files
resource "aws_s3_bucket_lifecycle_configuration" "input_files_bucket_lifecycle" {
  bucket = aws_s3_bucket.input_files_bucket.id # Reference the bucket ID

  rule {
    id     = "DeleteOldObjects"
    status = "Enabled"
    expiration {
      days = 90 # Objects will be deleted after 90 days
    }
    # Optional: Enable versioning management if needed
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 Bucket for Processed Output Results - now with a fun, unique name!
resource "aws_s3_bucket" "output_results_bucket" {
  bucket = "echo-reverie-${var.bucket_name_suffix}" # Fun: where the processed results echo out
  #acl    = "private"

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "ProcessedDataOutput" # More generic purpose
  }
}

# S3 Bucket Lifecycle Configuration for Output Results
resource "aws_s3_bucket_lifecycle_configuration" "output_results_bucket_lifecycle" {
  bucket = aws_s3_bucket.output_results_bucket.id # Reference the bucket ID

  rule {
    id     = "DeleteOldObjects"
    status = "Enabled"
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 Bucket to store Lambda deployment packages (artifacts) - now with a fun, unique name!
resource "aws_s3_bucket" "lambda_code_bucket" {
  bucket = "star-forge-scripts-${var.bucket_name_suffix}" # Fun: where the magical Lambda code is stored
  #acl    = "private"

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "LambdaDeployments" # More generic purpose
  }
}

# S3 Bucket Lifecycle Configuration for Lambda Code Artifacts
resource "aws_s3_bucket_lifecycle_configuration" "lambda_code_bucket_lifecycle" {
  bucket = aws_s3_bucket.lambda_code_bucket.id # Reference the bucket ID

  rule {
    id     = "DeleteOldArtifacts"
    status = "Enabled"
    expiration {
      days = 30 # Delete old Lambda zips after 30 days
    }
  }
}

# -----------------------------------------------------------------------------
# 2. IAM Role and Policy for Lambda
# -----------------------------------------------------------------------------

# IAM Role for the Lambda Function
# This role defines what permissions the Lambda function will have when executed.
resource "aws_iam_role" "text_processor_lambda_role" {
  name = "text-processor-lambda-role-${var.bucket_name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com" # Allows Lambda service to assume this role
        }
      },
    ]
  })

  tags = {
    Project = "CapstoneTextProcessor"
  }
}

# IAM Policy for Lambda to access S3 and Translate
resource "aws_iam_policy" "text_processor_lambda_policy" {
  name        = "text-processor-lambda-policy-${var.bucket_name_suffix}"
  description = "IAM policy for Lambda to access S3 buckets and AWS Translate."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissions for Lambda to write logs to CloudWatch
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      # Permissions to read objects from the input bucket
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.input_files_bucket.arn}/*" # Referencing input bucket
      },
      # Permissions to write objects to the output bucket
      {
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl", # Required for some S3 operations, ensures proper permissions
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.output_results_bucket.arn}/*" # Referencing output bucket
      },
      # Permissions to use AWS Translate (core functionality remains)
      {
        Action = [
          "translate:TranslateText",
        ]
        Effect   = "Allow"
        Resource = "*" # Translate API calls are generally not resource-specific
      },
    ]
  })

  tags = {
    Project = "CapstoneTextProcessor"
  }
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.text_processor_lambda_role.name # Referencing role
  policy_arn = aws_iam_policy.text_processor_lambda_policy.arn # Referencing policy
}

# -----------------------------------------------------------------------------
# 3. AWS Lambda Function
# -----------------------------------------------------------------------------

# Python Lambda code for text processing
# The content is embedded directly as a local variable.
locals {
  lambda_code = <<EOT
import json
import boto3
import os

s3_client = boto3.client('s3')
translate_client = boto3.client('translate')

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    try:
        s3_record = event['Records'][0']['s3']
        source_bucket_name = s3_record['bucket']['name']
        source_object_key = s3_record['object']['key']
    except KeyError as e:
        print(f"Error extracting S3 event details: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid S3 event structure.')
        }

    target_bucket_name = os.environ.get('TARGET_BUCKET_NAME')
    if not target_bucket_name:
        print("Error: TARGET_BUCKET_NAME environment variable not set for Lambda.")
        return {
            'statusCode': 500,
            'body': json.dumps('Lambda configuration error: Target bucket not defined.')
        }

    print(f"Processing file {source_object_key} from bucket {source_bucket_name}")

    try:
        response = s3_client.get_object(Bucket=source_bucket_name, Key=source_object_key)
        input_json_str = response['Body'].read().decode('utf-8')
        input_data = json.loads(input_json_str)
        print("Successfully read and parsed input JSON.")

        translated_output = {
            "original_file": source_object_key,
            "translations": []
        }

        # Ensure input_data is a list of text blocks to process
        if not isinstance(input_data, list):
            print("Warning: Input JSON is not a list. Attempting to treat it as a single text block.")
            input_data = [{"Text": input_data.get("Text", str(input_data)), "SourceLanguageCode": input_data.get("SourceLanguageCode", "auto"), "TargetLanguageCode": input_data.get("TargetLanguageCode", "en")}]

        for item in input_data:
            text_to_translate = item.get('Text')
            source_language_code = item.get('SourceLanguageCode', 'auto')
            target_language_code = item.get('TargetLanguageCode', 'en')

            if not text_to_translate:
                print(f"Skipping item due to missing 'Text' field: {item}")
                continue

            print(f"Translating: '{text_to_translate[:50]}...' from {source_language_code} to {target_language_code}")

            translate_response = translate_client.translate_text(
                Text=text_to_translate,
                SourceLanguageCode=source_language_code,
                TargetLanguageCode=target_language_code
            )
            translated_text = translate_response['TranslatedText']
            print("Translation successful.")

            translated_output['translations'].append({
                "original_text": text_to_translate,
                "translated_text": translated_text,
                "source_language": source_language_code,
                "target_language": target_language_code
            })

        output_json_str = json.dumps(translated_output, indent=2, ensure_ascii=False)
        output_object_key = source_object_key.replace('.json', '-translated.json')
        if '.json' not in source_object_key.lower():
            output_object_key = source_object_key + '-translated.json'

        print(f"Uploading translated output to {target_bucket_name}/{output_object_key}")
        s3_client.put_object(
            Bucket=target_bucket_name,
            Key=output_object_key,
            Body=output_json_str,
            ContentType='application/json'
        )
        print("Translated output uploaded successfully.")

        return {
            'statusCode': 200,
            'body': json.dumps('Translation processed and uploaded successfully!')
        }

    except Exception as e:
        print(f"Error during translation process: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing translation: {str(e)}')
        }
EOT
}

# Create a zip file containing the Lambda function code locally
resource "local_file" "lambda_zip" {
  content  = local.lambda_code
  filename = "lambda_function.zip"
}

# Upload the Lambda zip file to the S3 artifacts bucket
resource "aws_s3_object" "lambda_code_upload" {
  bucket = aws_s3_bucket.lambda_code_bucket.bucket # Referencing bucket
  key    = "lambda_function.zip"
  source = local_file.lambda_zip.filename
  # Fixed: Calculate ETag based on the content of the file, not its name.
  # This ensures changes in the Lambda code trigger an update.
  etag   = filemd5("${path.module}/lambda_function.zip")
}


# AWS Lambda Function for Text Processing
resource "aws_lambda_function" "text_processor_lambda" {
  function_name    = "text-processor-lambda-${var.bucket_name_suffix}"
  handler          = "index.lambda_handler" # Specifies the entry point in the Python code
  runtime          = "python3.9"            # Or a later compatible Python runtime
  role             = aws_iam_role.text_processor_lambda_role.arn # Referencing role
  timeout          = 30                     # Maximum execution time in seconds
  memory_size      = 128                    # Memory allocated to the Lambda function (MB)

  # Use the S3 object for the Lambda code
  s3_bucket = aws_s3_bucket.lambda_code_bucket.bucket # Referencing bucket
  s3_key    = aws_s3_object.lambda_code_upload.key
  # Fixed: Calculate source_code_hash based on the content string directly.
  # This ensures Lambda is updated when the embedded code changes.
  source_code_hash = base64sha256(local.lambda_code)

  environment {
    variables = {
      TARGET_BUCKET_NAME = aws_s3_bucket.output_results_bucket.bucket # Referencing bucket
    }
  }

  tags = {
    Project = "CapstoneTextProcessor"
  }
}

# -----------------------------------------------------------------------------
# 4. S3 Event Trigger
# -----------------------------------------------------------------------------

# Permission for S3 to invoke the Lambda function
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.text_processor_lambda.function_name # Referencing lambda
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_files_bucket.arn # Referencing bucket
}

# S3 Bucket Notification Configuration (Event Trigger)
# This sets up the input-files-bucket to invoke the Lambda function
resource "aws_s3_bucket_notification" "s3_bucket_notification" {
  bucket = aws_s3_bucket.input_files_bucket.id # Referencing bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.text_processor_lambda.arn # Referencing lambda
    events              = ["s3:ObjectCreated:*"] # Trigger when any object is created
    filter_prefix       = "input/" # Optional: Process only files in 'input/' prefix
    filter_suffix       = ".json"  # Optional: Process only .json files
  }

  # Ensure the Lambda permission is created before setting the notification
  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}

# -----------------------------------------------------------------------------
# Variables and Outputs
# -----------------------------------------------------------------------------

# Input variable for the S3 bucket name suffix
variable "bucket_name_suffix" {
  description = "A unique suffix for the S3 bucket names (e.g., your initials, project name). This ensures global uniqueness and adds a fun touch."
  type        = string
  default     = "celestial-vault-archive" # Fun and globally unique!
}

# Outputs for easy access to resource names
output "input_bucket_name" {
  description = "Name of the S3 bucket for input files."
  value       = aws_s3_bucket.input_files_bucket.bucket
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for processed output results."
  value       = aws_s3_bucket.output_results_bucket.bucket
}

output "lambda_code_bucket_name" {
  description = "Name of the S3 bucket for Lambda deployment code."
  value       = aws_s3_bucket.lambda_code_bucket.bucket
}

output "lambda_function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.text_processor_lambda.function_name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution."
  value       = aws_iam_role.text_processor_lambda_role.arn
}
