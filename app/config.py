from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # AssemblyAI
    assemblyai_api_key: Optional[str] = None
    
    # Supabase
    supabase_url: Optional[str] = None
    supabase_service_key: Optional[str] = None
    
    # Twilio
    twilio_account_sid: Optional[str] = None
    twilio_auth_token: Optional[str] = None
    twilio_phone_number: Optional[str] = None
    
    # Google Maps
    google_maps_api_key: Optional[str] = None
    
    # Onfleet
    onfleet_api_key: Optional[str] = None
    
    # n8n
    n8n_shift_webhook_url: Optional[str] = None
    n8n_driver_signup_webhook_url: Optional[str] = None
    
    # Environment
    environment: str = "development"
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
