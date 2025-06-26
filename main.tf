# Specify the AWS provider and region
provider "aws" {
  region = "us-east-1" 
}

# -----------------------------------------------------------------------------
# 1. S3 Buckets
# -----------------------------------------------------------------------------

# S3 Bucket for Input Files
resource "aws_s3_bucket" "input_files_bucket" {
  
  bucket = "whisper-scrolls-${var.bucket_name_suffix}" 
  acl    = "private" # Restrict public access by default

  # Enable versioning to keep a history of objects.
  versioning {
    enabled = true
  }

  # Lifecycle rule to automatically delete old objects after 90 days.
  lifecycle_rule {
    id      = "delete_old_objects"
    enabled = true

    expiration {
      days = 90 # Objects will be deleted after 90 days
    }
  }

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "DataIngestion"
  }
}

# S3 Bucket for Processed Output Results - now with a fun, unique name!
resource "aws_s3_bucket" "output_results_bucket" {
  # S3 bucket names must be globally unique across all of AWS.
  bucket = "echo-reverie-${var.bucket_name_suffix}" # Fun: where the processed results echo out
  acl    = "private"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "delete_old_objects"
    enabled = true

    expiration {
      days = 90
    }
  }

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "ProcessedDataOutput"
  }
}

# S3 Bucket to store Lambda deployment packages (artifacts) - now with a fun, unique name!
resource "aws_s3_bucket" "lambda_code_bucket" {
  # S3 bucket names must be globally unique across all of AWS.
  bucket = "star-forge-scripts-${var.bucket_name_suffix}" # Fun: where the magical Lambda code is stored
  acl    = "private"

  # A lifecycle rule can be added if you want to clean up old Lambda deployment zips
  lifecycle_rule {
    id      = "delete_old_artifacts"
    enabled = true

    expiration {
      days = 30 # Delete old Lambda zips after 30 days
    }
  }

  tags = {
    Project = "CapstoneTextProcessor"
    Purpose = "LambdaDeployments"
  }
}


# -----------------------------------------------------------------------------
# 2. IAM Role and Policy for Lambda
# -----------------------------------------------------------------------------

# IAM Role for the Lambda Function, this role defines what permissions the Lambda function will have when executed.
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
        Resource = "${aws_s3_bucket.input_files_bucket.arn}/*" # Referencing new bucket resource identifier
      },
      # Permissions to write objects to the output bucket
      {
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl", 
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.output_results_bucket.arn}/*" 
      },
      # Permissions to use AWS Translate (core functionality remains)
      {
        Action = [
          "translate:TranslateText",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = {
    Project = "CapstoneTextProcessor"
  }
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.text_processor_lambda_role.name 
  policy_arn = aws_iam_policy.text_processor_lambda_policy.arn 
}

# -----------------------------------------------------------------------------
# 3. AWS Lambda Function
# -----------------------------------------------------------------------------
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
        s3_record = event['Records'][0]['s3']
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
  bucket = aws_s3_bucket.lambda_code_bucket.bucket
  key    = "lambda_function.zip"
  source = local_file.lambda_zip.filename
  etag   = filemd5(local_file.lambda_zip.filename)
}

# AWS Lambda Function for Text Processing
resource "aws_lambda_function" "text_processor_lambda" { 
  function_name    = "text-processor-lambda-${var.bucket_name_suffix}"
  handler          = "index.lambda_handler" 
  runtime          = "python3.9"            
  role             = aws_iam_role.text_processor_lambda_role.arn 
  timeout          = 30                     
  memory_size      = 128                    

  # Use the S3 object for the Lambda code
  s3_bucket = aws_s3_bucket.lambda_code_bucket.bucket
  s3_key    = aws_s3_object.lambda_code_upload.key
  source_code_hash = aws_s3_object.lambda_code_upload.etag 
  environment {
    variables = {
      TARGET_BUCKET_NAME = aws_s3_bucket.output_results_bucket.bucket 
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
  function_name = aws_lambda_function.text_processor_lambda.function_name 
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_files_bucket.arn
}

# S3 Bucket Notification Configuration (Event Trigger)
resource "aws_s3_bucket_notification" "s3_bucket_notification" {
  bucket = aws_s3_bucket.input_files_bucket.id 

  lambda_function {
    lambda_function_arn = aws_lambda_function.text_processor_lambda.arn
    events              = ["s3:ObjectCreated:*"] 
    filter_prefix       = "input/" 
    filter_suffix       = ".json" 
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
  default     = "celestial-vault-archive" 
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
