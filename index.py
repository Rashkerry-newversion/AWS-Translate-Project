import json
import boto3
import os

s3 = boto3.client("s3")
translate = boto3.client("translate")

def lambda_handler(event, context):
    print("Event received:", event)
    
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    obj = s3.get_object(Bucket=bucket, Key=key)
    data = json.loads(obj['Body'].read().decode('utf-8'))

    output = {
        "translations": []
    }

    for item in data:
        translated = translate.translate_text(
            Text=item['Text'],
            SourceLanguageCode=item['SourceLanguageCode'],
            TargetLanguageCode=item['TargetLanguageCode']
        )
        output["translations"].append({
            "original": item['Text'],
            "translated": translated['TranslatedText'],
            "from": item['SourceLanguageCode'],
            "to": item['TargetLanguageCode']
        })

    output_key = key.replace('.json', '-translated.json')

    s3.put_object(
        Bucket=os.environ['TARGET_BUCKET_NAME'],
        Key=output_key,
        Body=json.dumps(output),
        ContentType="application/json"
    )

    return {
        'statusCode': 200,
        'body': 'Translation complete!'
    }
