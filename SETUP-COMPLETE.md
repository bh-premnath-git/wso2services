# 🔐 Complete Key Manager Setup Guide

# 1. Start services
docker compose up -d && ./scripts/wso2-toolkit.sh health

# 2. Automated Key Manager setup (NEW!)
./scripts/wso2-toolkit.sh setup-km
./scripts/wso2-toolkit.sh disable-resident-km
./scripts/wso2-toolkit.sh fix-mtls && docker restart wso2am

# 3. Verify everything
./scripts/wso2-toolkit.sh list-km
./scripts/wso2-toolkit.sh check-mtls
./scripts/wso2-toolkit.sh check-ssa-jwks

## API fixes

# Direct service calls (bypass gateway)
curl http://localhost:8001/health  # Forex
curl http://localhost:8002/health  # Ledger
curl http://localhost:8003/health  # Payment
curl http://localhost:8004/health  # Profile
curl http://localhost:8005/health  # Rule Engine
curl http://localhost:8006/health  # Wallet