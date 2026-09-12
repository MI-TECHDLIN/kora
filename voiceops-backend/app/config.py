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
    
    # Twilio (Outbound Calls & SMS notifications)
    account_sid: Optional[str] = None
    twilio_account_sid: Optional[str] = None
    primary_auth_token: Optional[str] = None
    twilio_auth_token: Optional[str] = None
    sid: Optional[str] = None
    twilio_api_key_sid: Optional[str] = None
    client_secret: Optional[str] = None
    twilio_api_key_secret: Optional[str] = None
    twilio_phone_number: Optional[str] = None
    twilio_from_number: Optional[str] = None
    
    @property
    def effective_twilio_account_sid(self) -> Optional[str]:
        return self.twilio_account_sid or self.account_sid

    @property
    def effective_twilio_auth_token(self) -> Optional[str]:
        return self.twilio_auth_token or self.primary_auth_token

    @property
    def effective_twilio_api_key_sid(self) -> Optional[str]:
        return self.twilio_api_key_sid or self.sid

    @property
    def effective_twilio_api_key_secret(self) -> Optional[str]:
        return self.twilio_api_key_secret or self.client_secret

    @property
    def effective_twilio_from_number(self) -> Optional[str]:
        return self.twilio_phone_number or self.twilio_from_number
    
    # Google Maps (Directions API for routes; navigation renders in-app, no deeplink)
    google_maps_api_key: Optional[str] = None
    google_directions_base_url: str = "https://maps.googleapis.com/maps/api/directions/json"
    
    # Onfleet (Optional - External logistics platform, use mock if not provided)
    onfleet_api_key: Optional[str] = None
    onfleet_base_url: str = "https://onfleet.com/api/v2"
    
    # n8n (Optional - Async dispatcher alerts via webhook)
    n8n_dispatcher_webhook_url: Optional[str] = None
    n8n_post_shift_webhook_url: Optional[str] = None
    n8n_driver_onboarding_webhook_url: Optional[str] = None
    dispatcher_escalation_email: Optional[str] = "tomarianoor@gmail.com"
    operator_report_email: Optional[str] = "tomarianoor@gmail.com"
    
    
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
