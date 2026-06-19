# ====================================================================
# StarLink Backend — Lightweight Token Server (server.py)
# ====================================================================
# This server generates secure, short-lived (1 hour TTL) LiveKit
# connection tokens for the iOS application.
# It runs with aiohttp (already installed as part of LiveKit SDK).
# ────────────────────────────────────────────────────────────────────

import os
import logging
import datetime
from aiohttp import web
from livekit import api
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("starlink-token-server")

# Retrieve and validate LiveKit credentials
LIVEKIT_URL = os.getenv("LIVEKIT_URL")
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")

if not all([LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET]):
    logger.warning("⚠️ Missing LiveKit credentials in backend/.env. Token generation will fail until configured.")

async def get_token(request: web.Request) -> web.Response:
    """
    HTTP GET endpoint to fetch a short-lived LiveKit token.
    Path: GET /api/token?identity=...&room=...
    """
    if not all([LIVEKIT_API_KEY, LIVEKIT_API_SECRET]):
        logger.error("Token generation requested, but LiveKit credentials are not set in .env")
        return web.json_response(
            {"error": "Server is misconfigured: missing LiveKit API credentials"},
            status=500,
            headers={"Access-Control-Allow-Origin": "*"}
        )

    # Read optional query parameters, with safe defaults
    identity = request.query.get("identity", "ios-hearing-aid-user")
    room_name = request.query.get("room", "starlink-translation")

    logger.info(f"Generating token — Identity: {identity}, Room: {room_name}")

    # Generate AccessToken with VideoGrants
    # TTL is set to 1 hour for production security.
    token = api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET) \
        .with_identity(identity) \
        .with_grants(api.VideoGrants(
            room_join=True,
            room=room_name
        )) \
        .with_ttl(datetime.timedelta(hours=1))

    try:
        jwt_token = token.to_jwt()
        response_data = {
            "token": jwt_token,
            "url": LIVEKIT_URL,
            "room": room_name,
            "identity": identity
        }

        # Define security-focused response headers
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
            "Pragma": "no-cache"
        }

        return web.json_response(response_data, headers=headers)
    except Exception as e:
        logger.error(f"Failed to generate JWT token: {e}", exc_info=True)
        return web.json_response(
            {"error": "Failed to generate connection token"}, 
            status=500,
            headers={"Access-Control-Allow-Origin": "*"}
        )

async def handle_options(request: web.Request) -> web.Response:
    """
    CORS Preflight endpoint.
    """
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "86400"
    }
    return web.Response(headers=headers)

async def health_check(request: web.Request) -> web.Response:
    """
    Simple health status endpoint.
    """
    status = "healthy" if all([LIVEKIT_API_KEY, LIVEKIT_API_SECRET]) else "degraded"
    return web.json_response({"status": status})

def create_app() -> web.Application:
    app = web.Application()
    app.router.add_get("/api/token", get_token)
    app.router.add_options("/api/token", handle_options)
    app.router.add_get("/health", health_check)
    return app

if __name__ == "__main__":
    host = os.getenv("TOKEN_SERVER_HOST", "0.0.0.0")
    port = int(os.getenv("TOKEN_SERVER_PORT", 8080))
    
    logger.info(f"Starting StarLink Token Server on http://{host}:{port}")
    web.run_app(create_app(), host=host, port=port)
