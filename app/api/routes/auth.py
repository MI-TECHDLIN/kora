from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from app.db.client import get_supabase_client


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
        
        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            user=response.user.model_dump() if hasattr(response.user, 'model_dump') else dict(response.user)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"OTP verification failed: {str(e)}"
        )
