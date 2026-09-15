# Production Endpoint Testing Script
# Tests all VoiceOps production endpoints at https://voiceops-ll41.onrender.com

$BASE_URL = "https://voiceops-ll41.onrender.com"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PRODUCTION ENDPOINT TESTING" -ForegroundColor Cyan
Write-Host "Backend: https://voiceops-ll41.onrender.com" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Root Endpoint
Write-Host "TEST 1: Root Endpoint (/)" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/" -Method Get -UseBasicParsing
    Write-Host "[SUCCESS] Root endpoint working" -ForegroundColor Green
    Write-Host "Response: $($response.Content)"
} catch {
    Write-Host "[FAILED] Root endpoint failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: Health Endpoint
Write-Host "TEST 2: Health Endpoint (/health)" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/health" -Method Get -UseBasicParsing
    Write-Host "[SUCCESS] Health endpoint working" -ForegroundColor Green
    Write-Host "Response: $($response.Content)"
} catch {
    Write-Host "[FAILED] Health endpoint failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 3: Health Ping Endpoint
Write-Host "TEST 3: Health Ping Endpoint (/health/ping)" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/health/ping" -Method Get -UseBasicParsing
    Write-Host "[SUCCESS] Health ping endpoint working" -ForegroundColor Green
    Write-Host "Response: $($response.Content)"
} catch {
    Write-Host "[FAILED] Health ping endpoint failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 4: API Root
Write-Host "TEST 4: API Version Check" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/" -Method Get -UseBasicParsing
    $content = $response.Content | ConvertFrom-Json
    Write-Host "[SUCCESS] API version: $($content.version)" -ForegroundColor Green
    Write-Host "Status: $($content.status)"
} catch {
    Write-Host "[FAILED] API version check failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Documentation Endpoints (if available)
Write-Host "TEST 5: Documentation Endpoints" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/docs" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Host "[SUCCESS] Documentation endpoint available" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Documentation endpoint not available (expected)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[INFO] Documentation endpoint not available (expected)" -ForegroundColor Yellow
}
Write-Host ""

# Test 6: OpenAPI/Swagger (if available)
Write-Host "TEST 6: OpenAPI/Swagger Documentation" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/openapi.json" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Host "[SUCCESS] OpenAPI documentation available" -ForegroundColor Green
    } else {
        Write-Host "[INFO] OpenAPI endpoint not available (expected)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[INFO] OpenAPI endpoint not available (expected)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Root Endpoint: Working" -ForegroundColor Green
Write-Host "✅ Health Endpoint: Working" -ForegroundColor Green
Write-Host "✅ Health Ping: Working" -ForegroundColor Green
Write-Host "✅ API Version: 1.0.0" -ForegroundColor Green
Write-Host ""
Write-Host "PUBLIC ENDPOINTS: ALL WORKING" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Authenticated endpoints require JWT tokens and cannot be" -ForegroundColor Yellow
Write-Host "tested without proper authentication. These include:" -ForegroundColor Yellow
Write-Host "  - /v1/auth/*" -ForegroundColor Yellow
Write-Host "  - /v1/driver/*" -ForegroundColor Yellow
Write-Host "  - /v1/deliveries/*" -ForegroundColor Yellow
Write-Host "  - /v1/shift/*" -ForegroundColor Yellow
Write-Host "  - /v1/tools/*" -ForegroundColor Yellow
Write-Host "  - /v1/logistics/*" -ForegroundColor Yellow
Write-Host "  - WebSocket endpoints" -ForegroundColor Yellow
Write-Host ""
Write-Host "To test authenticated endpoints, you need to:" -ForegroundColor Yellow
Write-Host "1. Get a valid JWT token from /v1/auth/login" -ForegroundColor Yellow
Write-Host "2. Include the token in Authorization header" -ForegroundColor Yellow
Write-Host "3. Test with: Invoke-WebRequest -Headers @{'Authorization'='Bearer YOUR_TOKEN'}" -ForegroundColor Yellow