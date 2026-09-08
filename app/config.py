from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # AssemblyAI
    assemblyai_api_key: Optional[str] = None
    assemblyai_agent_id: Optional[str] = None
    assemblyai_voice_agent_url: str = "wss://agents.assemblyai.com/v1/ws"
    assemblyai_transcription_url: str = "https://api.assemblyai.com/v2/transcript"
    
    # Supabase
    supabase_url: Optional[str] = None
    supabase_service_key: Optional[str] = None
    supabase_anon_key: Optional[str] = None
    
    # LiveKit (for outbound customer calls via SIP/PSTN)
    livekit_url: Optional[str] = None
    livekit_api_key: Optional[str] = None
    livekit_api_secret: Optional[str] = None
    livekit_sip_trunk_id: Optional[str] = None
    
    
    # Google Maps (Directions API for routes + deeplink for navigation)
    google_maps_api_key: Optional[str] = None
    google_directions_base_url: str = "https://maps.googleapis.com/maps/api/directions/json"
    
    # Vonage SMS (Customer text notifications - global coverage)
    vonage_api_key: Optional[str] = None
    vonage_api_secret: Optional[str] = None
    
    # Onfleet (Optional - External logistics platform, use mock if not provided)
    onfleet_api_key: Optional[str] = None
    onfleet_base_url: str = "https://onfleet.com/api/v2"
    
    # n8n (Optional - Async dispatcher alerts via webhook)
    n8n_dispatcher_webhook_url: Optional[str] = None
    
    
    # App Configuration
    jwt_secret: Optional[str] = None
    jwt_algorithm: str = "HS256"
    jwt_expiry_hours: int = 24
    environment: str = "development"
    
    class Config:
        env_file = ".env"
        case_sensitive = False
        extra = "ignore"  # Allow extra fields for backward compatibility


settings = Settings()
