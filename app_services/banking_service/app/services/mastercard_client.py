"""
Mastercard Open Finance API Client
Handles authentication and API calls to Mastercard/Finicity
"""
import httpx
import base64
import logging
import xml.etree.ElementTree as ET
from typing import Optional, Dict, List
from datetime import datetime, timedelta
from app.config import settings

logger = logging.getLogger(__name__)


class MastercardClient:
    """Client for Mastercard Open Finance API"""
    
    def __init__(self):
        self.partner_id = settings.MASTERCARD_PARTNER_ID
        self.partner_secret = settings.MASTERCARD_PARTNER_SECRET
        self.app_key = settings.MASTERCARD_APP_KEY
        self.base_url = settings.MASTERCARD_BASE_URL
        self.connect_url = settings.MASTERCARD_CONNECT_URL
        
        self.access_token: Optional[str] = None
        self.token_expires_at: Optional[datetime] = None
    
    def _xml_element_to_dict(self, element: ET.Element) -> Dict:
        """Convert XML element to dictionary recursively"""
        result = {}
        
        # Get element text
        if element.text and element.text.strip():
            result['_text'] = element.text.strip()
        
        # Get attributes
        if element.attrib:
            result.update(element.attrib)
        
        # Get children
        for child in element:
            child_data = self._xml_element_to_dict(child)
            
            # Handle multiple children with same tag
            if child.tag in result:
                if not isinstance(result[child.tag], list):
                    result[child.tag] = [result[child.tag]]
                result[child.tag].append(child_data)
            else:
                result[child.tag] = child_data
        
        # If only text, return just the text
        if len(result) == 1 and '_text' in result:
            return result['_text']
        
        return result
    
    def _parse_response(self, response: httpx.Response) -> Dict:
        """Parse XML or JSON response from Mastercard API"""
        content_type = response.headers.get('content-type', '').lower()
        
        if 'xml' in content_type:
            # Parse XML response
            root = ET.fromstring(response.text)
            
            # Special case for simple responses with single element
            if len(root) == 1 and root[0].text:
                # Single element like <token>value</token>
                return {root[0].tag: root[0].text}
            
            # Convert full XML tree to dict
            return self._xml_element_to_dict(root)
        else:
            # Parse JSON response
            return response.json()
    
    async def _get_access_token(self) -> str:
        """
        Get OAuth access token for API calls
        Token is valid for 1 hour
        """
        # Check if we have a valid cached token
        if self.access_token and self.token_expires_at:
            if datetime.now() < self.token_expires_at:
                return self.access_token
        
        # Request new token
        auth_string = f"{self.partner_id}:{self.partner_secret}"
        auth_bytes = base64.b64encode(auth_string.encode())
        
        # Create client with proper timeout and limits
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            follow_redirects=True,
            verify=True
        ) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/aggregation/v2/partners/authentication",
                    headers={
                        "Finicity-App-Key": self.app_key,
                        "Content-Type": "application/json"
                    },
                    json={
                        "partnerId": self.partner_id,
                        "partnerSecret": self.partner_secret
                    }
                )
                response.raise_for_status()
                
                # Mastercard returns XML, not JSON
                if 'xml' in response.headers.get('content-type', '').lower():
                    # Parse XML response
                    root = ET.fromstring(response.text)
                    token_elem = root.find('.//token')
                    if token_elem is not None:
                        self.access_token = token_elem.text
                    else:
                        raise ValueError("No token found in XML response")
                else:
                    # Try JSON parsing
                    data = response.json()
                    self.access_token = data["token"]
                
                # Finicity tokens are valid for 2 hours
                self.token_expires_at = datetime.now() + timedelta(hours=2, minutes=-5)
                
                logger.info("Successfully obtained Mastercard access token")
                return self.access_token
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to get access token: {e}")
                raise
            except Exception as e:
                logger.error(f"Error getting access token: {e}")
                raise
    
    async def create_customer(self, user_id: str, username: str) -> Dict:
        """
        Create a Mastercard customer for a user
        
        Args:
            user_id: Our internal user ID
            username: Username for Mastercard (can be user email or ID)
        
        Returns:
            Dictionary with customer data including customer_id
        """
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            follow_redirects=True,
            verify=True
        ) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/aggregation/v2/customers/testing",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key,
                        "Content-Type": "application/json"
                    },
                    json={"username": username}
                )
                response.raise_for_status()
                
                # Parse XML or JSON response
                data = self._parse_response(response)
                
                # Extract customer ID from different response formats
                customer_id = None
                if isinstance(data, dict):
                    # XML format: {id: 'value', username: 'value', ...}
                    customer_id = data.get('id') or data.get('customerId')
                    # Create consistent response format
                    result = {
                        "id": customer_id,
                        "username": data.get('username', username),
                        "createdDate": data.get('createdDate', str(datetime.now()))
                    }
                else:
                    result = data
                
                logger.info(f"Created Mastercard customer {customer_id} for user {user_id}")
                return result
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to create customer: {e}")
                raise
    
    async def get_customer(self, customer_id: str) -> Dict:
        """Get customer details"""
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.get(
                    f"{self.base_url}/aggregation/v1/customers/{customer_id}",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key
                    }
                )
                response.raise_for_status()
                return self._parse_response(response)
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to get customer: {e}")
                raise
    
    async def generate_connect_url(
        self, 
        customer_id: str, 
        redirect_uri: str,
        institution_id: Optional[str] = None,
        webhook_url: Optional[str] = None
    ) -> str:
        """
        Generate Mastercard Connect URL for account linking
        
        Args:
            customer_id: Mastercard customer ID
            redirect_uri: Where to redirect user after linking
            institution_id: Optional pre-selected institution
            webhook_url: Optional webhook for notifications
        
        Returns:
            Connect URL string
        """
        token = await self._get_access_token()
        
        # Build request payload
        payload = {
            "partnerId": self.partner_id,
            "customerId": customer_id,
            "redirectUri": redirect_uri
        }
        
        if institution_id:
            payload["institutionId"] = institution_id
        
        if webhook_url:
            payload["webhook"] = webhook_url
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/connect/v2/generate",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key,
                        "Content-Type": "application/json"
                    },
                    json=payload
                )
                response.raise_for_status()
                
                data = self._parse_response(response)
                connect_url = data.get("link") or data.get("url")
                
                if not connect_url:
                    logger.error(f"No connect URL in response: {data}")
                    raise ValueError("No connect URL returned from API")
                
                logger.info(f"Generated Connect URL for customer {customer_id}")
                return connect_url
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to generate Connect URL: {e}")
                if hasattr(e, 'response') and e.response is not None:
                    logger.error(f"Response text: {e.response.text}")
                raise
    
    async def get_customer_accounts(self, customer_id: str) -> List[Dict]:
        """
        Get all linked accounts for a customer
        
        Args:
            customer_id: Mastercard customer ID
        
        Returns:
            List of account dictionaries
        """
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.get(
                    f"{self.base_url}/aggregation/v1/customers/{customer_id}/accounts",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key
                    }
                )
                response.raise_for_status()
                
                data = self._parse_response(response)
                
                # Handle both XML and JSON response formats
                accounts = []
                if isinstance(data, dict):
                    accounts = data.get("accounts", data.get("account", []))
                    # Ensure it's a list
                    if not isinstance(accounts, list):
                        accounts = [accounts] if accounts else []
                
                logger.info(f"Retrieved {len(accounts)} accounts for customer {customer_id}")
                return accounts
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to get accounts: {e}")
                raise
    
    async def get_account_details(self, customer_id: str, account_id: str) -> Dict:
        """Get detailed information for a specific account"""
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.get(
                    f"{self.base_url}/aggregation/v1/customers/{customer_id}/accounts/{account_id}",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key
                    }
                )
                response.raise_for_status()
                return self._parse_response(response)
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to get account details: {e}")
                raise
    
    async def refresh_account(self, customer_id: str, account_id: str) -> Dict:
        """
        Refresh account data (balance, transactions)
        
        Args:
            customer_id: Mastercard customer ID
            account_id: Mastercard account ID
        
        Returns:
            Updated account data
        """
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(60.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/aggregation/v1/customers/{customer_id}/accounts/{account_id}",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key
                    }
                )
                response.raise_for_status()
                
                data = self._parse_response(response)
                logger.info(f"Refreshed account {account_id}")
                return data
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to refresh account: {e}")
                raise
    
    async def delete_account(self, customer_id: str, account_id: str) -> bool:
        """
        Delete an account from Mastercard
        
        Args:
            customer_id: Mastercard customer ID
            account_id: Mastercard account ID
        
        Returns:
            True if successful
        """
        token = await self._get_access_token()
        
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            verify=True
        ) as client:
            try:
                response = await client.delete(
                    f"{self.base_url}/aggregation/v1/customers/{customer_id}/accounts/{account_id}",
                    headers={
                        "Finicity-App-Token": token,
                        "Finicity-App-Key": self.app_key
                    }
                )
                response.raise_for_status()
                
                logger.info(f"Deleted account {account_id} from Mastercard")
                return True
                
            except httpx.HTTPError as e:
                logger.error(f"Failed to delete account: {e}")
                return False


# Global client instance
mastercard_client = MastercardClient()
