"""Quick test to verify marketplace service structure"""
import sys
import os

# Add paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'common'))

def test_imports():
    """Test that all modules can be imported"""
    try:
        print("Testing imports...")
        
        # Models
        from models import PSP, Corridor, Channel, CorridorRoute, Fee, RouteOverride
        print("✓ Models imported successfully")
        
        # Schemas
        from schemas import (
            PSPCreate, CorridorCreate, ChannelCreate,
            CorridorRouteCreate, FeeCreate, RouteOverrideCreate,
            RoutingRequest, RoutingResponse
        )
        print("✓ Schemas imported successfully")
        
        # Check enums
        from models.psp import PSPStatus, PSPType
        from models.corridor import CorridorStatus, RoutePolicy
        from models.corridor_route import RouteStatus
        from models.fee import FeeType
        print("✓ Enums imported successfully")
        
        print("\n✓ All imports successful!")
        return True
        
    except Exception as e:
        print(f"\n✗ Import failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def verify_structure():
    """Verify file structure"""
    print("\nVerifying file structure...")
    
    required_files = [
        'app/main.py',
        'app/database.py',
        'app/init_db.py',
        'app/models/__init__.py',
        'app/schemas/__init__.py',
        'app/routes/__init__.py',
        'app/repositories/base.py',
        'app/repositories/routing.py',
        'Dockerfile',
        'requirements.txt'
    ]
    
    base_path = os.path.dirname(__file__)
    all_exist = True
    
    for file_path in required_files:
        full_path = os.path.join(base_path, file_path)
        if os.path.exists(full_path):
            print(f"✓ {file_path}")
        else:
            print(f"✗ {file_path} - NOT FOUND")
            all_exist = False
    
    return all_exist

if __name__ == "__main__":
    print("=" * 60)
    print("Marketplace Service Structure Verification")
    print("=" * 60)
    
    structure_ok = verify_structure()
    imports_ok = test_imports()
    
    print("\n" + "=" * 60)
    if structure_ok and imports_ok:
        print("✓ VERIFICATION PASSED")
    else:
        print("✗ VERIFICATION FAILED")
    print("=" * 60)
