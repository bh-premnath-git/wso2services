"""Adapter manager for handling multiple payment processors."""

import logging
from typing import Dict, Optional, Any
from decimal import Decimal

from .base import PaymentAdapter
from .exceptions import ValidationError, PaymentError

logger = logging.getLogger(__name__)


class AdapterManager:
    """Manages multiple payment adapters and routes requests to the appropriate one."""
    
    def __init__(self) -> None:
        """Initialize the adapter manager."""
        self._adapters: Dict[str, PaymentAdapter] = {}
        self._default_adapter: Optional[str] = None
    
    def register_adapter(
        self, 
        name: str, 
        adapter: PaymentAdapter, 
        set_as_default: bool = False
    ) -> None:
        """Register a payment adapter.
        
        Args:
            name: Unique identifier for this adapter (e.g., "stripe", "custom")
            adapter: PaymentAdapter instance
            set_as_default: Whether to set this as the default adapter
        """
        if not name or not isinstance(name, str):
            raise ValueError("Adapter name must be a non-empty string")
        
        if not isinstance(adapter, PaymentAdapter):
            raise ValueError(f"Adapter must be an instance of PaymentAdapter, got {type(adapter)}")
        
        self._adapters[name.lower()] = adapter
        logger.info(f"Registered payment adapter: {name}")
        
        # Set as default if requested or if this is the first adapter
        if set_as_default or (len(self._adapters) == 1 and not self._default_adapter):
            self._default_adapter = name.lower()
            logger.info(f"Set {name} as default payment adapter")
    
    def get_adapter(self, name: Optional[str] = None) -> PaymentAdapter:
        """Get a payment adapter by name.
        
        Args:
            name: Adapter name. If None, returns the default adapter.
            
        Returns:
            PaymentAdapter instance
            
        Raises:
            ValidationError: If adapter not found or no default set
        """
        # If no name provided, use default
        if name is None:
            if not self._default_adapter:
                raise ValidationError("No default payment adapter configured")
            name = self._default_adapter
        
        adapter_name = name.lower()
        
        if adapter_name not in self._adapters:
            available = ", ".join(self._adapters.keys())
            raise ValidationError(
                f"Payment adapter '{name}' not found. Available adapters: {available}"
            )
        
        return self._adapters[adapter_name]
    
    def list_adapters(self) -> Dict[str, Any]:
        """List all registered adapters.
        
        Returns:
            Dictionary with adapter names and their status
        """
        return {
            "adapters": list(self._adapters.keys()),
            "default": self._default_adapter,
            "count": len(self._adapters)
        }
    
    def has_adapter(self, name: str) -> bool:
        """Check if an adapter is registered.
        
        Args:
            name: Adapter name to check
            
        Returns:
            True if adapter exists, False otherwise
        """
        return name.lower() in self._adapters
    
    def remove_adapter(self, name: str) -> None:
        """Remove a registered adapter.
        
        Args:
            name: Adapter name to remove
            
        Raises:
            ValidationError: If adapter not found
        """
        adapter_name = name.lower()
        
        if adapter_name not in self._adapters:
            raise ValidationError(f"Payment adapter '{name}' not found")
        
        del self._adapters[adapter_name]
        logger.info(f"Removed payment adapter: {name}")
        
        # Clear default if it was removed
        if self._default_adapter == adapter_name:
            self._default_adapter = None
            # Set first available as new default if any exist
            if self._adapters:
                self._default_adapter = next(iter(self._adapters.keys()))
                logger.info(f"Set {self._default_adapter} as new default adapter")
    
    # Convenience methods that delegate to the default adapter
    
    async def create_payment(
        self,
        amount: Decimal,
        currency: str,
        adapter_name: Optional[str] = None,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """Create a payment using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.create_payment(amount, currency, **kwargs)
    
    async def capture_payment(
        self,
        payment_id: str,
        adapter_name: Optional[str] = None,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """Capture a payment using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.capture_payment(payment_id, **kwargs)
    
    async def refund_payment(
        self,
        payment_id: str,
        adapter_name: Optional[str] = None,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """Refund a payment using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.refund_payment(payment_id, **kwargs)
    
    async def cancel_payment(
        self,
        payment_id: str,
        adapter_name: Optional[str] = None,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """Cancel a payment using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.cancel_payment(payment_id, **kwargs)
    
    async def webhook_verify(
        self,
        payload: bytes,
        sig_header: str,
        adapter_name: Optional[str] = None
    ) -> Dict[str, Any]:
        """Verify webhook using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.webhook_verify(payload, sig_header)
    
    async def get_payment_status(
        self,
        payment_id: str,
        adapter_name: Optional[str] = None
    ) -> Dict[str, Any]:
        """Get payment status using the specified or default adapter."""
        adapter = self.get_adapter(adapter_name)
        return await adapter.get_payment_status(payment_id)


__all__ = ["AdapterManager"]
