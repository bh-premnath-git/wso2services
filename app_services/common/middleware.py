"""
Common middleware for all services.
Provides CORS configuration for cross-origin requests from UI.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


def add_cors_middleware(app: FastAPI, allow_origins: list = None):
    """
    Add CORS middleware to FastAPI app.
    
    Args:
        app: FastAPI application instance
        allow_origins: List of allowed origins. Default allows localhost with common ports.
    
    Example:
        from middleware import add_cors_middleware
        app = FastAPI()
        add_cors_middleware(app)
    """
    if allow_origins is None:
        # Default: Allow localhost with common frontend ports
        allow_origins = [
            "http://localhost:3000",  # React default
            "http://localhost:3001",
            "http://localhost:5173",  # Vite default
            "http://localhost:8080",  # Vue default
            "http://localhost:4200",  # Angular default
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5173",
            # Add your production origins here when needed
        ]
    
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allow_origins,
        allow_credentials=True,
        allow_methods=["*"],  # Allow all HTTP methods (GET, POST, PUT, DELETE, PATCH, OPTIONS)
        allow_headers=["*"],  # Allow all headers (Authorization, Content-Type, etc.)
        expose_headers=["*"],
        max_age=3600,  # Cache preflight requests for 1 hour
    )