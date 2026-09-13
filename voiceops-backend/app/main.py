from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.config import settings
from app.api.routes import health, auth, voice_agent, deliveries, driver, shift, tools
from app.api.websocket import voice


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print(f"VoiceOps backend starting in {settings.environment} mode")
    yield
    # Shutdown
    print("VoiceOps backend shutting down")


app = FastAPI(
    title="VoiceOps API",
    description="Backend for VoiceOps - Voice-first logistics driver companion",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
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
app.include_router(voice_agent.router, prefix="/v1", tags=["voice-agent"])
app.include_router(voice.router, tags=["websocket"])



@app.get("/")
async def root():
    return {
        "message": "VoiceOps API",
        "version": "1.0.0",
        "status": "running"
    }
