# WSO2 Money Transfer App - Complete Setup

Production-ready WSO2 API Manager 4.5.0 + WSO2 Identity Server 7.1.0 with PostgreSQL.

## ✅ What's Configured

- **PostgreSQL** - 4 databases (apim_db, shared_db, identity_db, shared_db_is)
- **WSO2 Identity Server 7.1.0** - External Key Manager
- **WSO2 API Manager 4.5.0** - API Gateway
- **All OAuth 2.0 Grant Types** - Ready to use
- **TOML Configuration** - Fixed and validated
- **Token Revocation** - Configured for external KM

## 🚀 Quick Start (5 Minutes)

### 1. Start Services


## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ API Call + Token
       ▼
┌─────────────────────┐
│  APIM Gateway       │ ◄─── Token Validation ─────┐
│  :8243 / :8280      │                            │
└──────┬──────────────┘                            │
       │                                           │
       │ Route to Backend                   ┌──────────────┐
       ▼                                    │  WSO2 IS     │
┌─────────────────────┐                    │  :9444       │
│  Backend Services   │                    │  (Key Mgr)   │
└─────────────────────┘                    └──────┬───────┘
                                                  │
Client ────── Get Token ──────────────────────────┘
              (OAuth2 Grants)

         ┌─────────────────┐
         │  PostgreSQL     │
         │  :5432          │
         │  4 Databases    │
         └─────────────────┘
```

## Support

For issues specific to:
- **WSO2 Products** - https://wso2.com/support
- **This Setup** - Check `docker logs` and `./scripts/wso2-toolkit.sh health`

---

## 🎉 Complete Toolkit Summary

| Script | Purpose | Commands | Status |
|--------|---------|----------|--------|
| `wso2-toolkit.sh` | Infrastructure & OAuth | 25 | ✅ |
| `api-manager.sh` | API Lifecycle | 10 | ✅ |
| `wso2is-user.sh` | User Management | 8 | ✅ |
| **Total** | **Everything!** | **43** | ✅ |

**Complete WSO2 platform management with enterprise-grade security!** 🚀🔒

docker compose down -v

docker compose up -d --build

# Check status
docker compose ps

# Watch logs until you see "Server startup completed"
docker logs wso2is -f  # Ctrl+C when ready
docker logs wso2am -f  # Ctrl+C when ready

./scripts/wso2-toolkit.sh health
./scripts/wso2-toolkit.sh setup-km
./scripts/wso2-toolkit.sh disable-resident-km
./scripts/wso2-toolkit.sh fix-mtls && docker compose restart wso2am wso2is
./scripts/wso2-toolkit.sh check-mtls
./scripts/wso2-toolkit.sh check-ssa-jwks
./scripts/wso2-toolkit.sh list-apps
./scripts/wso2-toolkit.sh create-app MyApp1 http://localhost:8080/callback

 ./scripts/wso2-toolkit.sh create-roles
 ./scripts/wso2-toolkit.sh list-roles

 ./scripts/api-manager.sh quick-deploy ForexAPI 1.0.0 /forex http://forex-service:8001

 ./scripts/api-manager.sh subscribe ${APP_ID} <forex-api-id>

