"""
Bank Account API Endpoints - DynamoDB Version
"""
from fastapi import APIRouter, HTTPException, status
from typing import List
import logging
from datetime import datetime, timezone
from decimal import Decimal
import uuid

from app.schemas import (
    ConnectRequest, ConnectResponse, BankAccount, BankAccountListResponse,
    BankAccountDetails, UnlinkAccountResponse, SetPrimaryAccountResponse
)
from app.services.mastercard_client import mastercard_client

router = APIRouter()
logger = logging.getLogger(__name__)


# Import singletons lazily to avoid circular imports
def _get_tables():
    """Lazy import to avoid circular dependency"""
    from app import main
    return main._get_customers_table(), main._get_accounts_table(), main._get_logs_table()


def _to_decimal(value):
    """Convert float/int to Decimal for DynamoDB"""
    if value is None:
        return None
    return Decimal(str(value))


def _from_decimal(value):
    """Convert Decimal to float for JSON"""
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return value


def _serialize_item(item: dict) -> dict:
    """Convert Python types to DynamoDB-compatible types"""
    result = {}
    for key, value in item.items():
        if value is None:
            continue
        elif isinstance(value, datetime):
            result[key] = value.isoformat()
        elif isinstance(value, (int, float)):
            result[key] = _to_decimal(value)
        elif isinstance(value, bool):
            result[key] = value
        else:
            result[key] = str(value)
    return result


def _deserialize_item(item: dict) -> dict:
    """Convert DynamoDB types to Python types and map fields for schema"""
    result = {}
    for key, value in item.items():
        if isinstance(value, Decimal):
            result[key] = _from_decimal(value)
        else:
            result[key] = value
    
    # Map account_id to id for BankAccount schema
    if 'account_id' in result and 'id' not in result:
        result['id'] = result['account_id']
    
    return result


@router.post("/{user_id}/bank-accounts/connect", response_model=ConnectResponse)
async def generate_connect_url(
    user_id: str,
    request: ConnectRequest
):
    """
    Generate Mastercard Connect URL for bank account linking
    
    **Flow:**
    1. Check if user has Mastercard customer ID
    2. If not, create new Mastercard customer
    3. Generate Connect URL
    4. Log the connection attempt
    5. Return URL to frontend
    
    **Frontend Usage:**
    ```javascript
    const response = await fetch('/api/v1/user123/bank-accounts/connect', {
        method: 'POST',
        body: JSON.stringify({ redirect_uri: 'https://myapp.com/callback' })
    });
    const data = await response.json();
    window.location.href = data.connect_url;  // Redirect user
    ```
    """
    try:
        customers_table, accounts_table, logs_table = _get_tables()
        
        # Check if Mastercard customer exists
        response = customers_table.get_item(Key={"user_id": user_id})
        mc_customer = response.get("Item")
        
        if not mc_customer:
            # Create new Mastercard customer
            logger.info(f"Creating Mastercard customer for user {user_id}")
            
            mc_data = await mastercard_client.create_customer(
                user_id=user_id,
                username=f"user_{user_id}"
            )
            
            # Save to DynamoDB
            mc_customer = {
                "user_id": user_id,
                "mastercard_customer_id": mc_data["id"],
                "username": mc_data.get("username"),
                "status": "active",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat()
            }
            
            customers_table.put_item(Item=_serialize_item(mc_customer))
        
        # Generate Connect URL
        connect_url = await mastercard_client.generate_connect_url(
            customer_id=mc_customer["mastercard_customer_id"],
            redirect_uri=request.redirect_uri,
            institution_id=request.institution_id,
            webhook_url=request.webhook_url
        )
        
        # Log connection attempt
        log_id = str(uuid.uuid4())
        log_entry = {
            "log_id": log_id,
            "user_id": user_id,
            "action": "connect_initiated",
            "status": "pending",
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        logs_table.put_item(Item=_serialize_item(log_entry))
        
        session_id = str(uuid.uuid4())
        
        return ConnectResponse(
            connect_url=connect_url,
            session_id=session_id
        )
        
    except Exception as e:
        logger.error(f"Error generating Connect URL: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate Connect URL: {str(e)}"
        )


@router.get("/{user_id}/bank-accounts/callback")
async def handle_connect_callback(user_id: str):
    """
    Handle callback after user completes account linking
    
    **Flow:**
    1. User completes linking on Mastercard Connect
    2. Mastercard redirects back to our app
    3. Fetch linked accounts from Mastercard
    4. Save accounts to our database
    5. Return account list
    
    **Note:** In production, you might want to accept a `code` or `session_id` 
    parameter to validate the callback.
    """
    try:
        customers_table, accounts_table, logs_table = _get_tables()
        
        # Get Mastercard customer
        response = customers_table.get_item(Key={"user_id": user_id})
        mc_customer = response.get("Item")
        
        if not mc_customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Mastercard customer not found"
            )
        
        # Fetch accounts from Mastercard
        logger.info(f"Fetching accounts for customer {mc_customer['mastercard_customer_id']}")
        accounts = await mastercard_client.get_customer_accounts(
            customer_id=mc_customer["mastercard_customer_id"]
        )
        
        saved_accounts = []
        
        for account in accounts:
            # Check if account already exists (query by GSI)
            existing_response = accounts_table.query(
                IndexName="mastercard_account_id_index",
                KeyConditionExpression="mastercard_account_id = :mc_id",
                ExpressionAttributeValues={":mc_id": account["id"]}
            )
            
            account_id = str(uuid.uuid4())
            now = datetime.now(timezone.utc).isoformat()
            
            if existing_response.get("Items"):
                # Update existing account
                existing_account = existing_response["Items"][0]
                account_id = existing_account["account_id"]
                
                accounts_table.update_item(
                    Key={
                        "user_id": user_id,
                        "account_id": account_id
                    },
                    UpdateExpression="SET current_balance = :balance, available_balance = :avail, last_updated_at = :updated, #status = :status",
                    ExpressionAttributeNames={"#status": "status"},
                    ExpressionAttributeValues={
                        ":balance": _to_decimal(account.get("balance")),
                        ":avail": _to_decimal(account.get("availableBalance")),
                        ":updated": now,
                        ":status": "active"
                    }
                )
                
                # Fetch updated item
                updated_response = accounts_table.get_item(
                    Key={"user_id": user_id, "account_id": account_id}
                )
                saved_accounts.append(_deserialize_item(updated_response["Item"]))
            else:
                # Create new account record
                new_account = {
                    "user_id": user_id,
                    "account_id": account_id,
                    "mastercard_customer_id": mc_customer["mastercard_customer_id"],
                    "mastercard_account_id": account["id"],
                    "account_name": account.get("name", "Unknown Account"),
                    "account_number_masked": account.get("accountNumberDisplay", "****"),
                    "account_type": account.get("type", "unknown"),
                    "institution_id": str(account.get("institutionId", "")),
                    "institution_name": account.get("institutionName", "Unknown"),
                    "institution_logo_url": account.get("institutionLogo"),
                    "current_balance": account.get("balance"),
                    "available_balance": account.get("availableBalance"),
                    "currency": account.get("currency", "USD"),
                    "status": "active",
                    "consent_granted_at": now,
                    "is_verified": True,
                    "verification_method": "instant",
                    "is_primary": False,
                    "created_at": now,
                    "updated_at": now,
                    "last_updated_at": now
                }
                
                accounts_table.put_item(Item=_serialize_item(new_account))
                saved_accounts.append(new_account)
        
        # Log successful connection
        log_id = str(uuid.uuid4())
        log_entry = {
            "log_id": log_id,
            "user_id": user_id,
            "action": "connect_success",
            "status": "completed",
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        logs_table.put_item(Item=_serialize_item(log_entry))
        
        logger.info(f"Successfully linked {len(saved_accounts)} accounts for user {user_id}")
        
        return {
            "status": "success",
            "accounts_added": len(saved_accounts),
            "accounts": [BankAccount.model_validate(acc) for acc in saved_accounts]
        }
        
    except Exception as e:
        logger.error(f"Error handling callback: {e}")
        
        # Log failed connection
        try:
            _, _, logs_table = _get_tables()
            log_id = str(uuid.uuid4())
            log_entry = {
                "log_id": log_id,
                "user_id": user_id,
                "action": "connect_failed",
                "status": "error",
                "error_message": str(e),
                "created_at": datetime.now(timezone.utc).isoformat()
            }
            logs_table.put_item(Item=_serialize_item(log_entry))
        except Exception as log_error:
            logger.error(f"Failed to log error: {log_error}")
        
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process account linking: {str(e)}"
        )


@router.get("/{user_id}/bank-accounts", response_model=BankAccountListResponse)
async def list_bank_accounts(
    user_id: str,
    status_filter: str = "active"
):
    """
    List all linked bank accounts for a user
    
    **Query Parameters:**
    - status_filter: Filter by status (active, inactive, all)
    """
    try:
        accounts_table = _get_tables()[1]
        
        # Query by user_id (partition key)
        response = accounts_table.query(
            KeyConditionExpression="user_id = :uid",
            ExpressionAttributeValues={":uid": user_id}
        )
        
        accounts = [_deserialize_item(item) for item in response.get("Items", [])]
        
        # Filter by status if needed
        if status_filter != "all":
            accounts = [acc for acc in accounts if acc.get("status") == status_filter]
        
        # Filter out soft-deleted accounts
        accounts = [acc for acc in accounts if not acc.get("deleted_at")]
        
        return BankAccountListResponse(
            accounts=[BankAccount.model_validate(acc) for acc in accounts],
            total=len(accounts)
        )
        
    except Exception as e:
        logger.error(f"Error listing accounts: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list accounts: {str(e)}"
        )


@router.get("/{user_id}/bank-accounts/{account_id}", response_model=BankAccountDetails)
async def get_bank_account(
    user_id: str,
    account_id: str
):
    """Get detailed information for a specific bank account"""
    try:
        accounts_table = _get_tables()[1]
        
        response = accounts_table.get_item(
            Key={"user_id": user_id, "account_id": account_id}
        )
        
        account = response.get("Item")
        
        if not account or account.get("deleted_at"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Bank account not found"
            )
        
        return BankAccountDetails.model_validate(_deserialize_item(account))
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting account details: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get account details: {str(e)}"
        )


@router.post("/{user_id}/bank-accounts/{account_id}/refresh")
async def refresh_account_balance(
    user_id: str,
    account_id: str
):
    """
    Refresh account balance from Mastercard
    
    **Note:** This triggers a real-time data fetch from the bank.
    Use sparingly to avoid rate limits.
    """
    try:
        accounts_table = _get_tables()[1]
        
        # Get existing account
        response = accounts_table.get_item(
            Key={"user_id": user_id, "account_id": account_id}
        )
        
        account = response.get("Item")
        
        if not account or account.get("deleted_at"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Bank account not found"
            )
        
        # Refresh from Mastercard
        mc_account = await mastercard_client.refresh_account(
            customer_id=account["mastercard_customer_id"],
            account_id=account["mastercard_account_id"]
        )
        
        # Update database
        now = datetime.now(timezone.utc).isoformat()
        accounts_table.update_item(
            Key={"user_id": user_id, "account_id": account_id},
            UpdateExpression="SET current_balance = :balance, available_balance = :avail, last_updated_at = :updated",
            ExpressionAttributeValues={
                ":balance": _to_decimal(mc_account.get("balance")),
                ":avail": _to_decimal(mc_account.get("availableBalance")),
                ":updated": now
            }
        )
        
        # Fetch updated item for response
        updated_response = accounts_table.get_item(
            Key={"user_id": user_id, "account_id": account_id}
        )
        updated_account = _deserialize_item(updated_response["Item"])
        
        return {
            "status": "refreshed",
            "balances": {
                "current": float(updated_account.get("current_balance", 0)),
                "available": float(updated_account.get("available_balance", 0)),
                "updated_at": updated_account.get("last_updated_at")
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error refreshing account: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to refresh account: {str(e)}"
        )


@router.delete("/{user_id}/bank-accounts/{account_id}", response_model=UnlinkAccountResponse)
async def unlink_bank_account(
    user_id: str,
    account_id: str
):
    """
    Unlink a bank account
    
    **Note:** This performs a soft delete. The account record remains in the database
    but is marked as deleted.
    """
    try:
        accounts_table = _get_tables()[1]
        
        # Get existing account
        response = accounts_table.get_item(
            Key={"user_id": user_id, "account_id": account_id}
        )
        
        account = response.get("Item")
        
        if not account or account.get("deleted_at"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Bank account not found"
            )
        
        # Soft delete in our database
        now = datetime.now(timezone.utc).isoformat()
        accounts_table.update_item(
            Key={"user_id": user_id, "account_id": account_id},
            UpdateExpression="SET deleted_at = :deleted, #status = :status",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":deleted": now,
                ":status": "inactive"
            }
        )
        
        # Optionally delete from Mastercard
        # await mastercard_client.delete_account(
        #     customer_id=account["mastercard_customer_id"],
        #     account_id=account["mastercard_account_id"]
        # )
        
        logger.info(f"Unlinked account {account_id} for user {user_id}")
        
        return UnlinkAccountResponse(
            status="unlinked",
            message="Bank account successfully unlinked",
            account_id=account_id
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error unlinking account: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to unlink account: {str(e)}"
        )


@router.post("/{user_id}/bank-accounts/{account_id}/set-primary", response_model=SetPrimaryAccountResponse)
async def set_primary_account(
    user_id: str,
    account_id: str
):
    """Set an account as the primary funding source"""
    try:
        accounts_table = _get_tables()[1]
        
        # Get the target account
        response = accounts_table.get_item(
            Key={"user_id": user_id, "account_id": account_id}
        )
        
        account = response.get("Item")
        
        if not account or account.get("deleted_at"):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Bank account not found"
            )
        
        # Get all user accounts
        all_accounts_response = accounts_table.query(
            KeyConditionExpression="user_id = :uid",
            ExpressionAttributeValues={":uid": user_id}
        )
        
        # Unset other primary accounts
        for acc in all_accounts_response.get("Items", []):
            if acc["account_id"] != account_id and acc.get("is_primary"):
                accounts_table.update_item(
                    Key={"user_id": user_id, "account_id": acc["account_id"]},
                    UpdateExpression="SET is_primary = :false",
                    ExpressionAttributeValues={":false": False}
                )
        
        # Set this account as primary
        accounts_table.update_item(
            Key={"user_id": user_id, "account_id": account_id},
            UpdateExpression="SET is_primary = :true",
            ExpressionAttributeValues={":true": True}
        )
        
        return SetPrimaryAccountResponse(
            status="updated",
            account_id=account_id,
            is_primary=True
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error setting primary account: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to set primary account: {str(e)}"
        )
