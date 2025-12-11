"""Repository for runtime routing queries"""
from typing import List, Optional
from sqlalchemy.orm import Session, joinedload
from datetime import datetime
from ..models.corridor import Corridor
from ..models.channel import Channel
from ..models.corridor_route import CorridorRoute, RouteStatus
from ..models.fee import Fee
from ..models.route_override import RouteOverride


class RoutingRepository:
    """Repository for runtime routing queries"""

    def __init__(self, db: Session):
        self.db = db

    def get_corridor(
        self,
        source_country: str,
        dest_country: str,
        source_currency: str,
        dest_currency: str
    ) -> Optional[Corridor]:
        """Get corridor by source/dest country and currency"""
        return self.db.query(Corridor).filter(
            Corridor.source_country == source_country.upper(),
            Corridor.dest_country == dest_country.upper(),
            Corridor.source_currency == source_currency.upper(),
            Corridor.dest_currency == dest_currency.upper()
        ).first()

    def get_channel_by_code(self, code: str) -> Optional[Channel]:
        """Get channel by code"""
        return self.db.query(Channel).filter(
            Channel.code == code.upper()
        ).first()

    def get_corridor_routes(
        self,
        corridor_id: str,
        channel_id: str,
        amount: float
    ) -> List[CorridorRoute]:
        """Get active corridor routes that match the criteria"""
        query = self.db.query(CorridorRoute).options(
            joinedload(CorridorRoute.psp),
            joinedload(CorridorRoute.fees),
            joinedload(CorridorRoute.overrides)
        ).filter(
            CorridorRoute.corridor_id == corridor_id,
            CorridorRoute.channel_id == channel_id,
            CorridorRoute.status == RouteStatus.ACTIVE
        )

        # Filter by amount if constraints exist
        routes = []
        for route in query.all():
            # Check amount constraints
            if route.min_amount is not None and amount < route.min_amount:
                continue
            if route.max_amount is not None and amount > route.max_amount:
                continue
            routes.append(route)

        # Sort by priority (ascending) and weight (descending)
        routes.sort(key=lambda r: (r.priority, -r.weight))
        return routes

    def get_active_fee(self, corridor_route_id: str) -> Optional[Fee]:
        """Get the currently active fee for a corridor route"""
        now = datetime.utcnow()
        
        return self.db.query(Fee).filter(
            Fee.corridor_route_id == corridor_route_id,
            (Fee.effective_from == None) | (Fee.effective_from <= now),
            (Fee.effective_to == None) | (Fee.effective_to >= now)
        ).first()

    def get_route_overrides(
        self,
        corridor_route_id: str,
        segment_type: str,
        segment_value: str
    ) -> List[RouteOverride]:
        """Get route overrides for a specific segment"""
        return self.db.query(RouteOverride).filter(
            RouteOverride.corridor_route_id == corridor_route_id,
            RouteOverride.segment_type == segment_type,
            RouteOverride.segment_value == segment_value
        ).all()

    def get_all_corridors(self) -> List[Corridor]:
        """Get all active corridors for runtime listing"""
        return self.db.query(Corridor).filter(
            Corridor.status == "ACTIVE"
        ).all()

    def get_all_channels(self) -> List[Channel]:
        """Get all consumer-visible channels"""
        return self.db.query(Channel).filter(
            Channel.is_consumer_visible == True
        ).all()
