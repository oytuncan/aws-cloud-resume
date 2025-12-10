import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('ZiyaretciSayaci')

def lambda_handler(event, context):
    # Favicon kontrolü (Aynen kalsın)
    path = event.get('rawPath', '/')
    if 'favicon.ico' in path:
        return {
            'statusCode': 404,
            'body': 'Favicon yok'
        }

    # Veritabanı işlemleri (Aynen kalsın)
    response = table.get_item(Key={'id': 'sayac'})
    
    if 'Item' in response:
        ziyaret_sayisi = int(response['Item']['count'])
    else:
        ziyaret_sayisi = 0

    ziyaret_sayisi += 1

    table.put_item(Item={'id': 'sayac', 'count': ziyaret_sayisi})

    # --- DEĞİŞEN KISIM BURASI ---
    # Artık 'headers' göndermiyoruz. 
    # Çünkü Terraform'daki 'aws_lambda_function_url' bloğu bunu otomatik yapıyor.
    return {
        'statusCode': 200,
        'body': json.dumps({'count': ziyaret_sayisi})
    }