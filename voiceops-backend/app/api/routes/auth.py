from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from app.db.client import get_supabase_client
from app.integrations.n8n_client import trigger_driver_onboarding_background


router = APIRouter()


class SendOTPRequest(BaseModel):
    phone: str


class VerifyOTPRequest(BaseModel):
    phone: str
    token: str


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    user: dict


@router.post("/otp/send")
async def send_otp(request: SendOTPRequest):
    """Send OTP to phone number."""
    try:
        supabase = get_supabase_client()
        # Send OTP via Supabase Auth
        response = supabase.auth.sign_in_with_otp({
            "phone": request.phone
        })
        
        return {"message": "OTP sent successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to send OTP: {str(e)}"
        )


@router.post("/otp/verify", response_model=AuthResponse)
async def verify_otp(request: VerifyOTPRequest):
    """Verify OTP and return JWT tokens."""
    try:
        supabase = get_supabase_client()
        # Verify OTP with Supabase
        response = supabase.auth.verify_otp({
            "phone": request.phone,
            "token": request.token,
            "type": "sms"
        })
        
        if not response or not response.session:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid OTP"
            )
        
        user_dict = response.user.model_dump() if hasattr(response.user, 'model_dump') else dict(response.user)
        user_id = user_dict.get("id")

        # Check if driver is already registered; if new, trigger onboarding workflow
        try:
            driver_check = supabase.table("drivers").select("id").eq("id", user_id).execute()
            if not driver_check.data:
                metadata = user_dict.get("user_metadata", {}) or {}
                driver_name = metadata.get("name") or metadata.get("full_name") or f"Driver {request.phone[-4:]}"
                supabase.table("drivers").upsert({
                    "id": user_id,
                    "phone": request.phone,
                    "name": driver_name
                }).execute()

                trigger_driver_onboarding_background(
                    driver_id=user_id,
                    driver_name=driver_name,
                    phone=request.phone,
                    email=user_dict.get("email")
                )
        except Exception:
            pass  # Avoid blocking login if onboarding trigger encounters any issue

        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            user=user_dict
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"OTP verification failed: {str(e)}"
        )
