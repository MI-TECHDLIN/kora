from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.config import settings
from app.api.routes import (
    health,
    auth,
    voice_agent,
    deliveries,
    driver,
    shift,
    tools,
    locations,
    pod,
    fleet,
    routes,
    logistics,
)
from app.api.websocket.driver_ws import router as driver_ws_router
from app.api.websocket.voice import router as voice_router
from app.dispatch.order_dispatch import get_order_dispatcher
from app.services.self_ping_service import self_ping_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print(f"Kora backend starting in {settings.environment} mode")
    if not settings.tomtom_api_key:
        print("[Config] WARNING: TOMTOM_API_KEY is not set. Traffic-aware ETA calculations and proactive reroute suggestions will be disabled.")
    dispatcher = get_order_dispatcher()
    await dispatcher.start()
    
    # Start self-ping service to keep Render instance awake
    await self_ping_service.start()
    
    yield
    # Shutdown
    print("Kora backend shutting down")
    await self_ping_service.stop()
    await dispatcher.stop()


app = FastAPI(
    title="Kora API",
    description="Backend for Kora - Voice-first logistics driver companion",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware - dynamic based on environment
cors_origins = (
    [origin.strip() for origin in settings.allowed_origins.split(",") if origin.strip()]
    if settings.environment == "production" and settings.allowed_origins != "*"
    else ["*"]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health.router, prefix="/health", tags=["health"])
app.include_router(auth.router, prefix="/v1/auth", tags=["auth"])
app.include_router(driver.router, prefix="/v1/driver", tags=["driver"])
app.include_router(deliveries.router, prefix="/v1/deliveries", tags=["deliveries"])
app.include_router(shift.router, prefix="/v1/shift", tags=["shift"])
app.include_router(tools.router, prefix="/v1/tools", tags=["tools"])
app.include_router(logistics.router, prefix="/v1/logistics", tags=["logistics"])
app.include_router(voice_agent.router, prefix="/v1", tags=["voice-agent"])
app.include_router(locations.router, prefix="/v1", tags=["locations"])
app.include_router(pod.router, prefix="/v1", tags=["pod"])
app.include_router(fleet.router, prefix="/v1/fleet", tags=["fleet"])
app.include_router(routes.router, prefix="/v1", tags=["routes"])
app.include_router(driver_ws_router, tags=["websocket"])
app.include_router(voice_router, tags=["voice-websocket"])



@app.get("/")
async def root():
    return {
        "message": "Kora API",
        "version": "1.0.0",
        "status": "running"
    }
