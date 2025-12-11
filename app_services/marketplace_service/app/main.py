"""Marketplace Service - Payment routing and PSP catalog"""
import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from middleware import add_cors_middleware

from .database import init_db
from .routes import (
    admin_psps,
    admin_corridors,
    admin_channels,
    admin_routes,
    admin_fees,
    runtime
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    log.info("Starting Marketplace Service...")
    
    # Initialize database tables
    try:
        init_db()
        log.info("Database tables initialized successfully")
    except Exception as e:
        log.error(f"Failed to initialize database: {e}")
        raise
    
    log.info("Marketplace Service startup complete")
    yield
    log.info("Marketplace Service shutting down...")


app = FastAPI(
    title="Marketplace Service",
    version="1.0.0",
    description="Payment routing catalog and PSP configuration service",
    lifespan=lifespan
)

# Add CORS middleware
add_cors_middleware(app)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "marketplace_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint with service information"""
    return {
        "service": "Marketplace Service",
        "message": "Payment routing and PSP catalog API",
        "version": "1.0.0",
        "endpoints": {
            "admin": [
                "/admin/psps",
                "/admin/corridors",
                "/admin/channels",
                "/admin/routes",
                "/admin/fees"
            ],
            "runtime": [
                "/runtime/routing/candidates",
                "/runtime/corridors",
                "/runtime/channels"
            ]
        },
        "docs": "/docs"
    }


# Exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    log.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "error": str(exc)
        }
    )


# Include routers
app.include_router(admin_psps.router)
app.include_router(admin_corridors.router)
app.include_router(admin_channels.router)
app.include_router(admin_routes.router)
app.include_router(admin_fees.router)
app.include_router(runtime.router)


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("MARKETPLACE_SERVICE_PORT", "8009"))
    uvicorn.run(app, host="0.0.0.0", port=port)
