from fastapi import FastAPI, HTTPException, Request, Header
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional, Literal
from decimal import Decimal
import os
import sys
import logging

# Add common and parent modules to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

parent_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if parent_path not in sys.path:
    sys.path.insert(0, parent_path)

from middleware import add_cors_middleware
from config import config

# Import adapters
from adapters import AdapterManager
from adapters.stripe import StripeAdapter
from adapters.custom import CustomAdapter
from adapters.exceptions import PaymentError, ValidationError

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Payment Service",
    version="1.0.0",
    description="Payment processing and orchestration service with multiple payment adapters"
)

add_cors_middleware(app)

# Initialize adapter manager
adapter_manager = AdapterManager()


@app.on_event("startup")
async def startup_event():
    """Initialize payment adapters on startup."""
    logger.info("Initializing payment adapters...")
    
    # Initialize Stripe adapter if configured
    if config.STRIPE_SECRET_KEY and config.STRIPE_WEBHOOK_SECRET:
        try:
            stripe_adapter = StripeAdapter(
                api_key=config.STRIPE_SECRET_KEY,
                webhook_secret=config.STRIPE_WEBHOOK_SECRET,
                enable_test_mode=True  # Set based on environment
            )
            adapter_manager.register_adapter("stripe", stripe_adapter, set_as_default=True)
            logger.info("✓ Stripe adapter initialized and set as default")
        except Exception as e:
            logger.error(f"Failed to initialize Stripe adapter: {e}")
    else:
        logger.warning("Stripe credentials not configured, skipping Stripe adapter")
    
    # Initialize custom adapter as fallback
    try:
        custom_adapter = CustomAdapter(expected_signature="test_signature")
        adapter_manager.register_adapter("custom", custom_adapter)
        logger.info("✓ Custom adapter initialized")
    except Exception as e:
        logger.error(f"Failed to initialize custom adapter: {e}")
    
    # Log registered adapters
    adapters_info = adapter_manager.list_adapters()
    logger.info(f"Registered adapters: {adapters_info}")


# ==================== Request/Response Models ====================

class PaymentCreateRequest(BaseModel):
    """Request model for creating a payment."""
    amount: Decimal = Field(..., gt=0, description="Payment amount")
    currency: str = Field(..., min_length=3, max_length=3, description="Three-letter ISO currency code")
    customer_id: Optional[str] = Field(None, description="Customer identifier")
    description: Optional[str] = Field(None, max_length=500, description="Payment description")
    adapter: Optional[Literal["stripe", "custom"]] = Field(None, description="Payment adapter to use (default: stripe)")
    metadata: Optional[dict] = Field(None, description="Additional metadata")


class PaymentResponse(BaseModel):
    """Response model for payment operations."""
    payment_id: str
    status: str
    amount: Decimal
    currency: str
    timestamp: datetime
    adapter: str
    details: Optional[dict] = None


class RefundRequest(BaseModel):
    """Request model for refunding a payment."""
    amount: Optional[Decimal] = Field(None, gt=0, description="Refund amount (partial refund if specified)")
    reason: Optional[str] = Field(None, max_length=500, description="Refund reason")
    adapter: Optional[Literal["stripe", "custom"]] = Field(None, description="Payment adapter to use")


class WebhookVerifyRequest(BaseModel):
    """Request model for webhook verification."""
    signature: str = Field(..., description="Webhook signature header")
    adapter: Optional[Literal["stripe", "custom"]] = Field(None, description="Payment adapter to use")


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "payment_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint with service information."""
    adapters_info = adapter_manager.list_adapters()
    return {
        "service": "Payment Service",
        "version": "1.0.0",
        "message": "Payment processing and orchestration API with multi-adapter support",
        "adapters": adapters_info,
        "endpoints": {
            "health": "/health",
            "adapters": "/adapters",
            "create_payment": "POST /payments",
            "get_payment": "GET /payments/{payment_id}",
            "capture_payment": "POST /payments/{payment_id}/capture",
            "refund_payment": "POST /payments/{payment_id}/refund",
            "cancel_payment": "POST /payments/{payment_id}/cancel",
            "webhook": "POST /webhooks/{adapter}"
        }
    }


@app.get("/adapters")
async def list_adapters():
    """List all registered payment adapters."""
    return adapter_manager.list_adapters()


@app.post("/payments", response_model=PaymentResponse, status_code=201)
async def create_payment(payment: PaymentCreateRequest):
    """Create a new payment using the specified adapter."""
    try:
        # Convert to int for smallest currency unit (e.g., cents)
        amount_cents = int(payment.amount * 100)
        
        # Create payment using adapter
        result = await adapter_manager.create_payment(
            amount=Decimal(amount_cents),
            currency=payment.currency.upper(),
            adapter_name=payment.adapter,
            customer_id=payment.customer_id,
            description=payment.description,
            metadata=payment.metadata or {}
        )
        
        return PaymentResponse(
            payment_id=result.get("id", "unknown"),
            status=result.get("status", "unknown"),
            amount=payment.amount,
            currency=payment.currency.upper(),
            timestamp=datetime.now(),
            adapter=payment.adapter or adapter_manager._default_adapter or "unknown",
            details=result
        )
    except ValidationError as e:
        logger.error(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        logger.error(f"Payment error: {e}")
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error(f"Unexpected error creating payment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create payment: {str(e)}")


@app.get("/payments/{payment_id}")
async def get_payment(payment_id: str, adapter: Optional[str] = None):
    """Get payment status and details."""
    try:
        result = await adapter_manager.get_payment_status(
            payment_id=payment_id,
            adapter_name=adapter
        )
        
        return {
            "payment_id": payment_id,
            "adapter": adapter or adapter_manager._default_adapter,
            "details": result
        }
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.error(f"Error retrieving payment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve payment: {str(e)}")


@app.post("/payments/{payment_id}/capture")
async def capture_payment(payment_id: str, adapter: Optional[str] = None):
    """Capture a previously authorized payment."""
    try:
        result = await adapter_manager.capture_payment(
            payment_id=payment_id,
            adapter_name=adapter
        )
        
        return {
            "payment_id": payment_id,
            "status": "captured",
            "adapter": adapter or adapter_manager._default_adapter,
            "details": result
        }
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error(f"Error capturing payment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to capture payment: {str(e)}")


@app.post("/payments/{payment_id}/refund")
async def refund_payment(payment_id: str, refund: RefundRequest):
    """Refund a payment (full or partial)."""
    try:
        kwargs = {}
        if refund.amount:
            # Convert to smallest currency unit
            kwargs["amount"] = Decimal(int(refund.amount * 100))
        if refund.reason:
            kwargs["reason"] = refund.reason
        
        result = await adapter_manager.refund_payment(
            payment_id=payment_id,
            adapter_name=refund.adapter,
            **kwargs
        )
        
        return {
            "payment_id": payment_id,
            "status": "refunded",
            "adapter": refund.adapter or adapter_manager._default_adapter,
            "details": result
        }
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error(f"Error refunding payment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to refund payment: {str(e)}")


@app.post("/payments/{payment_id}/cancel")
async def cancel_payment(payment_id: str, adapter: Optional[str] = None, reason: Optional[str] = None):
    """Cancel a pending payment."""
    try:
        kwargs = {}
        if reason:
            kwargs["reason"] = reason
        
        result = await adapter_manager.cancel_payment(
            payment_id=payment_id,
            adapter_name=adapter,
            **kwargs
        )
        
        return {
            "payment_id": payment_id,
            "status": "cancelled",
            "adapter": adapter or adapter_manager._default_adapter,
            "details": result
        }
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error(f"Error cancelling payment: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to cancel payment: {str(e)}")


@app.post("/webhooks/{adapter}")
async def handle_webhook(
    adapter: Literal["stripe", "custom"],
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="Stripe-Signature"),
    x_custom_signature: Optional[str] = Header(None, alias="X-Custom-Signature")
):
    """Handle payment processor webhooks."""
    try:
        # Get raw payload
        payload = await request.body()
        
        # Determine signature based on adapter
        if adapter == "stripe":
            if not stripe_signature:
                raise HTTPException(status_code=400, detail="Missing Stripe-Signature header")
            sig_header = stripe_signature
        elif adapter == "custom":
            if not x_custom_signature:
                raise HTTPException(status_code=400, detail="Missing X-Custom-Signature header")
            sig_header = x_custom_signature
        else:
            raise HTTPException(status_code=400, detail=f"Unknown adapter: {adapter}")
        
        # Verify and process webhook
        result = await adapter_manager.webhook_verify(
            payload=payload,
            sig_header=sig_header,
            adapter_name=adapter
        )
        
        logger.info(f"Webhook received from {adapter}: {result.get('type', 'unknown')}")
        
        return {
            "status": "verified",
            "adapter": adapter,
            "event": result
        }
    except ValidationError as e:
        logger.error(f"Webhook validation failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except PaymentError as e:
        logger.error(f"Webhook processing error: {e}")
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.error(f"Unexpected webhook error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to process webhook: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)