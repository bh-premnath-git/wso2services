"""
Configuration for Profile Service with ComplyCube KYC Integration
"""
import os
from pathlib import Path
from typing import List

# Get the parent directory to import common config
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from common.config import config as common_config


class ProfileServiceConfig:
    """Profile Service Configuration with KYC settings"""
    
    # Service Info
    SERVICE_NAME = "profile-service"
    SERVICE_VERSION = "1.0.0"
    SERVICE_PORT = 8004
    SERVICE_HOST = "0.0.0.0"
    
    # Database Configuration
    DATABASE_URL = common_config.get_database_url("profile_db")
    REDIS_URL = "redis://redis:6379/3"  # Using DB 3 for profile service
    
    # ComplyCube API Configuration
    COMPLYCUBE_API_KEY = os.getenv("COMPLYCUBE_API_KEY", "")
    COMPLYCUBE_BASE_URL = os.getenv("COMPLYCUBE_BASE_URL", "https://api.complycube.com")
    
    # KYC Flow Configuration
    KYC_SUCCESS_URL = os.getenv("KYC_SUCCESS_URL", "http://localhost:8004/kyc/success")
    KYC_CANCEL_URL = os.getenv("KYC_CANCEL_URL", "http://localhost:8004/kyc/cancel")
    
    # Default KYC Check Types for Flow
    # proof_of_address_check is included - user will be prompted to upload address proof documents
    KYC_BASIC_CHECKS = ["identity_check", "document_check", "proof_of_address_check"]
    KYC_ENHANCED_CHECKS = ["identity_check", "document_check", "proof_of_address_check", "extensive_screening_check"]
    
    # Additional checks that can be triggered separately if needed
    KYC_ADDRESS_CHECK = "proof_of_address_check"
    
    # Logging Configuration
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")


# Global configuration instance
settings = ProfileServiceConfig()