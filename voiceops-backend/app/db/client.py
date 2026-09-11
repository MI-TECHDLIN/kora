from supabase import create_client, Client
from app.config import settings
from typing import Optional


_supabase_client: Optional[Client] = None


def get_supabase_client() -> Client:
    """Get Supabase client singleton."""
    global _supabase_client
    
    if _supabase_client is None:
        if not settings.supabase_url or not settings.supabase_service_key:
            raise ValueError("Supabase URL and service key must be set in environment variables")
        _supabase_client = create_client(settings.supabase_url, settings.supabase_service_key)
    
    return _supabase_client


# Export as a property for lazy loading
class SupabaseProxy:
    def __getattr__(self, name):
        return getattr(get_supabase_client(), name)

supabase = SupabaseProxy()
