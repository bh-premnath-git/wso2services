"""
Centralized configuration management for all app services
Loads configuration from environment variables
"""
import os
from typing import Optional
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(dotenv_path=env_path)


class Config:
    """Base configuration class"""

    # ============================================================================
    # Database Configuration
    # ============================================================================
    POSTGRES_USER: str = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD: str = os.getenv("POSTGRES_PASSWORD", "your_secure_password_here")
    POSTGRES_MAX_CONNECTIONS: int = int(os.getenv("POSTGRES_MAX_CONNECTIONS", "300"))

    # WSO2 Database Configuration
    WSO2_DB_USER: str = os.getenv("WSO2_DB_USER", "wso2carbon")
    WSO2_DB_PASSWORD: str = os.getenv("WSO2_DB_PASSWORD", "wso2carbon")
    WSO2_APIM_DB: str = os.getenv("WSO2_APIM_DB", "apim_db")
    WSO2_SHARED_DB: str = os.getenv("WSO2_SHARED_DB", "shared_db")
    WSO2_SHARED_DB_IS: str = os.getenv("WSO2_SHARED_DB_IS", "shared_db_is")
    WSO2_IDENTITY_DB: str = os.getenv("WSO2_IDENTITY_DB", "identity_db")
    WSO2_DB_HOST: str = os.getenv("WSO2_DB_HOST", "postgres")
    WSO2_DB_PORT: int = int(os.getenv("WSO2_DB_PORT", "5432"))

    # ============================================================================
    # WSO2 Admin Configuration
    # ============================================================================
    WSO2_ADMIN_USERNAME: str = os.getenv("WSO2_ADMIN_USERNAME", "admin")
    WSO2_ADMIN_PASSWORD: str = os.getenv("WSO2_ADMIN_PASSWORD", "admin")

    # ============================================================================
    # WSO2 Service URLs
    # ============================================================================
    WSO2_IS_HOST: str = os.getenv("WSO2_IS_HOST", "wso2is")
    WSO2_IS_PORT: int = int(os.getenv("WSO2_IS_PORT", "9443"))
    WSO2_AM_HOST: str = os.getenv("WSO2_AM_HOST", "wso2am")
    WSO2_AM_PORT: int = int(os.getenv("WSO2_AM_PORT", "9443"))

    # ============================================================================
    # SMTP Email Configuration
    # ============================================================================
    SMTP_HOST: str = os.getenv("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SENDER_EMAIL: str = os.getenv("SENDER_EMAIL", "")
    SENDER_PASSWORD: str = os.getenv("SENDER_PASSWORD", "")

    @classmethod
    def validate_smtp_config(cls) -> bool:
        """Validate that required SMTP configuration is present"""
        if not cls.SENDER_EMAIL or not cls.SENDER_PASSWORD:
            raise ValueError(
                "SMTP configuration incomplete. Please set SENDER_EMAIL and "
                "SENDER_PASSWORD in your .env file"
            )
        return True

    @classmethod
    def get_database_url(
        cls,
        db_name: str,
        user: Optional[str] = None,
        password: Optional[str] = None,
        host: Optional[str] = None,
        port: Optional[int] = None
    ) -> str:
        """
        Generate PostgreSQL database URL

        Args:
            db_name: Name of the database
            user: Database user (defaults to WSO2_DB_USER)
            password: Database password (defaults to WSO2_DB_PASSWORD)
            host: Database host (defaults to WSO2_DB_HOST)
            port: Database port (defaults to WSO2_DB_PORT)

        Returns:
            PostgreSQL connection URL
        """
        user = user or cls.WSO2_DB_USER
        password = password or cls.WSO2_DB_PASSWORD
        host = host or cls.WSO2_DB_HOST
        port = port or cls.WSO2_DB_PORT

        return f"postgresql://{user}:{password}@{host}:{port}/{db_name}"


# Create a singleton instance for easy import
config = Config()


# Export commonly used configurations
__all__ = [
    "Config",
    "config",
]
