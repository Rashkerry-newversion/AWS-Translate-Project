# AWS Automated Language Translation Pipeline (IaC with Terraform)

## Project Overview

This project implements a fully automated language translation pipeline on AWS, leveraging Infrastructure-as-Code (IaC) principles with Terraform. The core of the solution integrates Amazon S3 for efficient object storage and AWS Translate for seamless language translation.

The workflow is designed to be completely serverless:

When a JSON file containing text for translation is uploaded to a designated S3 "request" bucket, an AWS Lambda function is automatically triggered by an S3 event.

This Lambda function processes the incoming request, utilizes AWS Translate to perform the language translation, and then stores the translated output as a new JSON file in a separate S3 "response" bucket.

This project serves as a comprehensive demonstration of building a scalable, resilient, and automated cloud solution, showcasing best practices in cloud infrastructure deployment, serverless computing, and API integration.

## Objectives

## The primary objectives of this project are to

1. Understand AWS Translate and Amazon S3: Gain in-depth knowledge of their capabilities and best use cases for this architecture.

2. Establish S3 Buckets: Create two distinct S3 buckets: one for incoming translation requests (request-bucket) and another for storing the translated output (response-bucket).

3. Define IAM Policies: Craft a precise IAM policy and role to grant the Lambda function only the necessary permissions to interact with AWS Translate and S3.

4. Master AWS CLI & Boto3:  Ensure proficient local setup and usage of AWS CLI for administrative tasks and Boto3 (AWS SDK for Python) for programmatic interaction within the Lambda function.

5. Implement IaC with Terraform: Design and deploy the entire AWS infrastructure using Terraform, including:

6. S3 buckets with appropriate lifecycle policies.

7. An IAM role with specific access permissions for translation and storage.

8. The AWS Lambda function hosting the translation logic.

9. S3 event triggers to automate Lambda invocation upon new object creation.

10. Develop Core Translation Logic: Write a robust Python script using Boto3 to:

11. Parse input JSON files containing language metadata.

12. Submit text blocks to AWS Translate.

13. Format and save the translated text into a new JSON structure.

14. Upload the final translated results to the response-bucket.

15. Automate with AWS Lambda: Package the Python script as a serverless AWS Lambda function, triggered by S3 object creation events, ensuring an efficient and cost-effective workflow.

16. Thorough Testing and Documentation: Conduct comprehensive testing, identify and resolve any bugs, optimize code for performance, and provide detailed documentation for future reference and reproducibility.

## Architecture Diagram

+-------------------+       +-----------------------+       +-------------------+
|                   |       |                       |       |                   |
|   S3 (Request)    |       |     AWS Lambda        |       |   S3 (Response)   |
|   Bucket          |----->|   (Translation        |----->|   Bucket          |
|  (Input JSONs)    | Event |   Processor)          |       |  (Output JSONs)   |
|                   |       |                       |       |                   |
+-------------------+       +-----------+-----------+       +-------------------+
                                        |
                                        | Invokes
                                        v
                            +-----------------------+
                            |                       |
                            |     AWS Translate     |
                            |   (Performs Actual    |
                            |     Translation)      |
                            |                       |
                            +-----------------------+

## Tools Used
1. AWS Services: S3, Lambda, IAM, Translate, CloudWatch

2. IaC Tool: Terraform

3. Programming Language: Python

4. AWS SDK: Boto3

5. Version Control: Git / GitHub

6. Command Line Interface: AWS CLI, Terraform CLI

## Free Tier Compliance

This project is designed with AWS Free Tier limits in mind, but it is critical to monitor your usage to avoid unexpected charges, especially during extensive testing.

1. S3: 5 GB of standard storage, 20,000 Get Requests, and 2,000 Put Requests per month.

2. IAM: Always free.

3. Terraform: No charge for Terraform usage itself; you only pay for the AWS resources provisioned.

4. AWS Translate: 2 million characters per month for the first 12 months.

5. AWS Lambda: 1 million requests and 400,000 GB-seconds of compute time per month.

## Step-by-Step Building Process & Deployment Guide

This section provides a detailed, step-by-step guide to setting up, deploying, and testing your AWS Automated Language Translation Pipeline. It includes points where you can insert screenshots for your school assignment.


## Phase 1: Local Setup & Prerequisites

Install and configure Git, Terraform, and on your machine. Then proceed to setting up your project.

## Phase 2: Project Setup and Terraform Initialization

This phase involves setting up your local project directory and initializing Terraform.

## Clone the Repository

Create and Clone GitHub repository to your local machine:

git clone [https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git)

(Replace YOUR_USERNAME and YOUR_REPO_NAME with your actual GitHub details).

Navigate into the cloned directory:

cd YOUR_REPO_NAME

Inspect Terraform Configuration (main.tf):

Open the main.tf file (provided in this repository) .

Familiarize yourself with the resources defined: S3 buckets, IAM role/policy, Lambda function, and S3 event notification.

Important: Locate the variable "bucket_name_suffix" block. You must change the default value to something unique across all of AWS (e.g., your initials followed by a random string like jds-translate-xyz123). This suffix will be appended to your S3 bucket names to ensure they are globally unique.

## Initialize Terraform

In your terminal, within the project directory, run:

terraform init

This command initializes the working directory, downloads the necessary AWS provider plugins, and sets up the backend for Terraform state management.

## Phase 3: Terraform Deployment

Now you're ready to deploy your AWS infrastructure.

## Review the Terraform Plan

Run:

terraform plan

## Apply the Terraform Configuration

If the plan looks correct, proceed to apply the configuration.

Run:

terraform apply

Terraform will show the plan again and prompt you to confirm by typing yes. Type yes and press Enter.

Terraform will then proceed to provision the resources in your AWS account. This process may take a few minutes.

## Verify Resources in AWS Console

Log in to the AWS Management Console.

1. S3: Navigate to the S3 service and confirm that your three buckets (translation-request-bucket-YOUR-SUFFIX, translation-response-bucket-YOUR-SUFFIX, and lambda-artifacts-bucket-YOUR-SUFFIX) have been created.

2. Lambda: Go to the Lambda service and verify that your TranslationProcessorLambda-YOUR-SUFFIX function exists.

3. IAM: Check the IAM service to confirm the TranslationProcessorLambdaRole-YOUR-SUFFIX and its associated policy are present.

## Phase 4: Testing the Translation Pipeline

With the infrastructure deployed, it's time to test the automated translation process.

Prepare Sample Input JSON:

An example input file (sample_input_1.json) is provided in the sample_input/ directory of this repository. This file demonstrates the expected structure for your input translation requests.

You can create your own test_input.json file following this structure. Ensure you use valid language codes (e.g., en, fr, de, es, ja, etc.).

## Upload Input JSON to Request Bucket

Upload your prepared JSON file to the translation-request-bucket-YOUR-SUFFIX.

## Option A: AWS S3 Console

Navigate to your translation-request-bucket-YOUR-SUFFIX in the S3 console.

Click the "Upload" button, then "Add files", and select your sample_input_1.json (or your custom test file).

Click "Upload".

## Option B: AWS CLI

aws s3 cp sample_input/sample_input_1.json s3://translation-request-bucket-your-unique-suffix/sample_input_1.json

(Remember to replace your-unique-suffix with your actual suffix).

## Monitor Lambda Execution Logs (CloudWatch)

1. Immediately after uploading the file, navigate to the AWS Lambda console.

2. Select your TranslationProcessorLambda-YOUR-SUFFIX function.

3. Click on the "Monitor" tab, then click "View logs in CloudWatch".

This will open the CloudWatch Logs console. Look for a new log stream (a folder-like icon) that appears shortly after your upload. Click on it to view the real-time logs of your Lambda function's execution. You should see messages indicating the processing of the file, translation requests, and successful upload.

## Retrieve Translated Output from Response Bucket

1. Go back to the AWS S3 console.

2. Navigate to your translation-response-bucket-YOUR-SUFFIX.

3. You should find a new file (e.g., sample_input_1-translated.json) in this bucket. This file contains the translated text.

4. Download the file and open it to verify the translations.

## Phase 5: Troubleshooting & Cleanup

This final phase covers debugging common issues and ensuring proper resource deletion.

## Troubleshooting Common Issues

Lambda Not Triggering:

Verify the S3 event notification configuration in the Lambda console (under the "Configuration" tab, "Triggers" section).

Check aws_lambda_permission resource in main.tf to ensure S3 has permission to invoke the Lambda.

## Lambda Errors / Failed Translations

1. Primary Tool: CloudWatch Logs (as described in Phase 4, Step 3). Look for ERROR messages or Python tracebacks.

2. IAM Permissions: Ensure the TranslationProcessorLambdaRole has all necessary permissions: s3:GetObject on the request bucket, s3:PutObject/s3:PutObjectAcl on the response bucket, translate:TranslateText (resource *), and CloudWatch logging permissions.

3. Input JSON Format: A common mistake is an incorrectly formatted input JSON. The Lambda function expects a specific structure (an array of objects with Text, SourceLanguageCode, TargetLanguageCode).

4. Lambda Timeout/Memory: For very large translation tasks, the Lambda's default timeout (30 seconds) or memory (128MB) might be insufficient. Adjust these values in main.tf under the aws_lambda_function resource if needed.

## Cleaning Up AWS Resources (Crucial for Cost Management)

Empty S3 Buckets: Before Terraform can delete an S3 bucket, it must be empty.

Manually delete all objects from translation-request-bucket-YOUR-SUFFIX and translation-response-bucket-YOUR-SUFFIX using the AWS S3 console or the AWS CLI.

## Replace with your actual bucket names

aws s3 rm s3://translation-request-bucket-your-unique-suffix --recursive
aws s3 rm s3://translation-response-bucket-your-unique-suffix --recursive

The lambda-artifacts-bucket should be automatically emptied and deleted by Terraform as part of the destroy process, since it only contains the Lambda zip file managed by Terraform.

## Destroy Terraform Resources

Navigate back to your project directory in the terminal.

## Run the Terraform destroy command

terraform destroy

Terraform will list all resources it plans to destroy. You will be prompted to confirm by typing yes. Type yes and press Enter.

This will delete all AWS resources defined in your main.tf file.

Conclusion
This project successfully demonstrates the power of Infrastructure-as-Code with Terraform to deploy a serverless, automated language translation pipeline on AWS. By leveraging S3, Lambda, and AWS Translate, we've created a scalable and efficient solution for processing translation requests. The detailed step-by-step guide and integration points for screenshots should make this a valuable resource for your capstone assignment.