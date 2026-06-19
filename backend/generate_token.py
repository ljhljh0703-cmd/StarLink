import os
import datetime
from livekit import api
from dotenv import load_dotenv

load_dotenv()

url = os.getenv("LIVEKIT_URL")
api_key = os.getenv("LIVEKIT_API_KEY")
api_secret = os.getenv("LIVEKIT_API_SECRET")

if not all([url, api_key, api_secret]):
    print("오류: backend/.env 파일에 LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET가 모두 작성되어 있어야 토큰을 생성할 수 있습니다.")
    exit(1)

# Generate LiveKit Token
token = api.AccessToken(api_key, api_secret) \
    .with_identity("ios-hearing-aid-user") \
    .with_grants(api.VideoGrants(
        room_join=True,
        room="starlink-translation"
    )) \
    .with_ttl(datetime.timedelta(days=30))

try:
    jwt_token = token.to_jwt()
    print("\n=========================================================================")
    print(" 아래의 정보를 복사하여 StarLink/Config/AppConfig.swift 파일에 붙여넣으세요.")
    print("=========================================================================")
    print(f'static let livekitURL = "{url}"')
    print(f'static let livekitToken = "{jwt_token}"')
    print("=========================================================================\n")
except Exception as e:
    print(f"토큰 생성 중 오류가 발생했습니다: {e}")
