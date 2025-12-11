"""Database initialization script with sample data"""
import os
import sys

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from database import init_db, SessionLocal
from models.psp import PSP, PSPStatus, PSPType
from models.corridor import Corridor, CorridorStatus, RoutePolicy
from models.channel import Channel
from models.corridor_route import CorridorRoute, RouteStatus
from models.fee import Fee, FeeType


def seed_sample_data():
    """Seed database with sample data for testing"""
    db = SessionLocal()
    
    try:
        # Create sample PSPs
        psps = [
            PSP(
                id="stripe",
                name="Stripe",
                type=PSPType.CARD,
                status=PSPStatus.ACTIVE,
                capabilities=["payouts", "collections", "card-only"],
                regions_supported=["US", "IN", "GB", "EU"],
                metadata={"settlement_time_hours": 24, "requires_cvv": True}
            ),
            PSP(
                id="mastercard_send",
                name="Mastercard Send",
                type=PSPType.CARD,
                status=PSPStatus.ACTIVE,
                capabilities=["payouts"],
                regions_supported=["US", "IN", "MX"],
                metadata={"settlement_time_hours": 12}
            ),
            PSP(
                id="wise",
                name="Wise",
                type=PSPType.BANK,
                status=PSPStatus.ACTIVE,
                capabilities=["payouts", "bank-only"],
                regions_supported=["US", "IN", "GB", "EU", "AU"],
                metadata={"settlement_time_hours": 48}
            ),
        ]
        
        for psp in psps:
            existing = db.query(PSP).filter(PSP.id == psp.id).first()
            if not existing:
                db.add(psp)
        
        # Create sample corridors
        corridors = [
            Corridor(
                id="IN-US-INR-USD",
                source_country="IN",
                dest_country="US",
                source_currency="INR",
                dest_currency="USD",
                status=CorridorStatus.ACTIVE,
                default_route_policy=RoutePolicy.PRIORITY
            ),
            Corridor(
                id="US-IN-USD-INR",
                source_country="US",
                dest_country="IN",
                source_currency="USD",
                dest_currency="INR",
                status=CorridorStatus.ACTIVE,
                default_route_policy=RoutePolicy.PRIORITY
            ),
        ]
        
        for corridor in corridors:
            existing = db.query(Corridor).filter(Corridor.id == corridor.id).first()
            if not existing:
                db.add(corridor)
        
        # Create sample channels
        channels = [
            Channel(
                id="card_to_bank",
                code="CARD_TO_BANK",
                description="Card to bank transfer",
                is_consumer_visible=True
            ),
            Channel(
                id="bank_to_bank",
                code="BANK_TO_BANK",
                description="Bank to bank transfer",
                is_consumer_visible=True
            ),
        ]
        
        for channel in channels:
            existing = db.query(Channel).filter(Channel.id == channel.id).first()
            if not existing:
                db.add(channel)
        
        db.commit()
        
        # Create sample corridor routes
        routes = [
            CorridorRoute(
                id="IN-US-CARD-STRIPE",
                corridor_id="IN-US-INR-USD",
                channel_id="card_to_bank",
                psp_id="stripe",
                priority=1,
                weight=80,
                min_amount=1.0,
                max_amount=200000.0,
                status=RouteStatus.ACTIVE,
                metadata={"requires_cvv": True, "requires_address": True}
            ),
            CorridorRoute(
                id="IN-US-CARD-MC",
                corridor_id="IN-US-INR-USD",
                channel_id="card_to_bank",
                psp_id="mastercard_send",
                priority=2,
                weight=20,
                min_amount=1000.0,
                max_amount=500000.0,
                status=RouteStatus.ACTIVE,
                metadata={}
            ),
            CorridorRoute(
                id="IN-US-BANK-WISE",
                corridor_id="IN-US-INR-USD",
                channel_id="bank_to_bank",
                psp_id="wise",
                priority=1,
                weight=100,
                min_amount=100.0,
                max_amount=1000000.0,
                status=RouteStatus.ACTIVE,
                metadata={"requires_iban": True}
            ),
        ]
        
        for route in routes:
            existing = db.query(CorridorRoute).filter(CorridorRoute.id == route.id).first()
            if not existing:
                db.add(route)
        
        db.commit()
        
        # Create sample fees
        fees = [
            Fee(
                id="FEE-STRIPE-1",
                corridor_route_id="IN-US-CARD-STRIPE",
                fee_type=FeeType.MIXED,
                value_flat=50.0,
                value_percent=0.5,
                min_fee=50.0,
                max_fee=500.0
            ),
            Fee(
                id="FEE-MC-1",
                corridor_route_id="IN-US-CARD-MC",
                fee_type=FeeType.PERCENTAGE,
                value_percent=0.7,
                min_fee=100.0,
                max_fee=1000.0
            ),
            Fee(
                id="FEE-WISE-1",
                corridor_route_id="IN-US-BANK-WISE",
                fee_type=FeeType.FLAT,
                value_flat=200.0
            ),
        ]
        
        for fee in fees:
            existing = db.query(Fee).filter(Fee.id == fee.id).first()
            if not existing:
                db.add(fee)
        
        db.commit()
        print("✓ Sample data seeded successfully")
        
    except Exception as e:
        db.rollback()
        print(f"✗ Error seeding sample data: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    print("Initializing Marketplace database...")
    init_db()
    print("✓ Database tables created")
    
    print("\nSeeding sample data...")
    seed_sample_data()
    print("\n✓ Marketplace database initialization complete")
