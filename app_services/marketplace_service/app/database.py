"""Database connection and session management"""
import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from config import config

# Database configuration - supports both PostgreSQL and MySQL
MARKETPLACE_DB_NAME = os.getenv("MARKETPLACE_DB_NAME", "marketplace_db")
DB_TYPE = os.getenv("MARKETPLACE_DB_TYPE", "mysql")  # mysql or postgresql

if DB_TYPE.lower() == "mysql":
    # MySQL configuration
    DB_USER = os.getenv("MARKETPLACE_DB_USER", "root")
    DB_PASSWORD = os.getenv("MARKETPLACE_DB_PASSWORD", os.getenv("MYSQL_ROOT_PASSWORD", "root"))
    DB_HOST = os.getenv("MARKETPLACE_DB_HOST", "mysql")
    DB_PORT = int(os.getenv("MARKETPLACE_DB_PORT", "3306"))
    DATABASE_URL = f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{MARKETPLACE_DB_NAME}"
else:
    # PostgreSQL configuration (fallback)
    DATABASE_URL = config.get_database_url(
        db_name=MARKETPLACE_DB_NAME,
        user=config.POSTGRES_USER,
        password=config.POSTGRES_PASSWORD,
        host=config.WSO2_DB_HOST,
        port=config.WSO2_DB_PORT
    )

# Create engine
engine = create_engine(
    DATABASE_URL,
    pool_size=20,
    max_overflow=40,
    pool_pre_ping=True,
    echo=False
)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class for models
Base = declarative_base()


def get_db():
    """Dependency to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Initialize database tables"""
    Base.metadata.create_all(bind=engine)
