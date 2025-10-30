"""
Email service for sending verification emails
"""
import aiosmtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import random
import string
from typing import Dict
from datetime import datetime, timedelta
import sys
from pathlib import Path

# Add parent directory to path to import common modules
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from common.config import config


class EmailService:
    """Service for sending verification emails"""
    
    def __init__(
        self,
        smtp_host: str = None,
        smtp_port: int = None,
        sender_email: str = None,
        sender_password: str = None
    ):
        # Use centralized config values, allow override via parameters
        self.smtp_host = smtp_host or config.SMTP_HOST
        self.smtp_port = smtp_port or config.SMTP_PORT
        self.sender_email = sender_email or config.SENDER_EMAIL
        self.sender_password = sender_password or config.SENDER_PASSWORD

        # Validate configuration
        if not self.sender_email or not self.sender_password:
            raise ValueError(
                "Email configuration incomplete. Please set SENDER_EMAIL and "
                "SENDER_PASSWORD in your .env file"
            )
        
        # In-memory storage for verification codes (temporary)
        # In production, use Redis or database
        self.verification_codes: Dict[str, Dict] = {}
    
    def generate_verification_code(self) -> str:
        """Generate 6-digit verification code"""
        return ''.join(random.choices(string.digits, k=6))
    
    def store_verification_code(self, username: str, code: str) -> None:
        """Store verification code with expiry"""
        self.verification_codes[username] = {
            "code": code,
            "created_at": datetime.now(),
            "expires_at": datetime.now() + timedelta(minutes=15)
        }
    
    def verify_code(self, username: str, code: str) -> bool:
        """Verify the code for a username"""
        stored = self.verification_codes.get(username)
        if not stored:
            return False
        
        # Check if expired
        if datetime.now() > stored["expires_at"]:
            del self.verification_codes[username]
            return False
        
        # Check if code matches
        if stored["code"] == code:
            del self.verification_codes[username]
            return True
        
        return False
    
    def has_pending_verification(self, username: str) -> bool:
        """Check if user has pending verification code"""
        stored = self.verification_codes.get(username)
        if not stored:
            return False
        
        # Check if expired
        if datetime.now() > stored["expires_at"]:
            del self.verification_codes[username]
            return False
        
        return True
    
    async def send_verification_email(
        self,
        recipient_email: str,
        username: str,
        first_name: str
    ) -> str:
        """
        Send verification email with code
        Returns the verification code
        """
        
        # Generate verification code
        code = self.generate_verification_code()
        
        # Store the code
        self.store_verification_code(username, code)
        
        # Create email message
        message = MIMEMultipart("alternative")
        message["Subject"] = "Verify Your Account - WSO2 Services"
        message["From"] = self.sender_email
        message["To"] = recipient_email
        
        # Email body
        text_content = f"""
Hello {first_name},

Thank you for registering with WSO2 Services!

Your verification code is: {code}

This code will expire in 15 minutes.

Username: {username}

If you didn't create this account, please ignore this email.

Best regards,
WSO2 Services Team
"""
        
        html_content = f"""
<html>
  <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 5px;">
      <h2 style="color: #FF7300;">Welcome to WSO2 Services!</h2>
      <p>Hello <strong>{first_name}</strong>,</p>
      <p>Thank you for registering with WSO2 Services!</p>
      
      <div style="background-color: #f4f4f4; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <p style="margin: 0; font-size: 14px; color: #666;">Your verification code is:</p>
        <h1 style="margin: 10px 0; color: #FF7300; letter-spacing: 5px;">{code}</h1>
        <p style="margin: 0; font-size: 12px; color: #999;">This code will expire in 15 minutes</p>
      </div>
      
      <p><strong>Username:</strong> {username}</p>
      
      <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
      
      <p style="font-size: 12px; color: #999;">
        If you didn't create this account, please ignore this email.
      </p>
      
      <p style="margin-top: 20px;">
        Best regards,<br>
        <strong>WSO2 Services Team</strong>
      </p>
    </div>
  </body>
</html>
"""
        
        # Attach both plain text and HTML versions
        part1 = MIMEText(text_content, "plain")
        part2 = MIMEText(html_content, "html")
        message.attach(part1)
        message.attach(part2)
        
        # Send email
        try:
            await aiosmtplib.send(
                message,
                hostname=self.smtp_host,
                port=self.smtp_port,
                username=self.sender_email,
                password=self.sender_password,
                start_tls=True
            )
            return code
        except Exception as e:
            raise Exception(f"Failed to send email: {str(e)}")


# Global email service instance
email_service = EmailService()
