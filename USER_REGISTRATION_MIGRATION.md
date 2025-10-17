# User Registration Migration - From SCIM2 to Registration API

## What Changed

### ❌ Old Approach (setup_is_users_roles.sh)
- Created **both roles AND users** via SCIM2 API directly
- Users created with direct SCIM2 calls
- Tightly coupled role and user creation
- Users: `ops_user`, `finance`, `auditor`, `user`, `app_admin`

### ✅ New Approach (Separated & Modernized)

#### 1. **Role Creation** (setup_roles_only.sh)
- **Only creates roles** via SCIM2 API
- Roles: `ops_users`, `finance`, `auditor`, `user`, `app_admin`
- Runs during system setup (Step 6/10)

#### 2. **User Registration** (register_test_users.sh)
- **Registers users** via Profile Service `/register` endpoint
- Uses the new registration API we built
- Runs after APIs are deployed (Step 9/10)
- Users registered with proper validation:
  - Password strength check
  - Email validation
  - Username format validation

---

## File Changes

| File | Status | Purpose |
|------|--------|---------|
| `app_scripts/setup_is_users_roles.sh` | ⚠️ **Keep but deprecated** | Old combined script (still works) |
| `app_scripts/setup_roles_only.sh` | ✅ **New - Active** | Creates roles only |
| `app_scripts/register_test_users.sh` | ✅ **New - Active** | Registers users via API |
| `complete_startup.sh` | ✅ **Updated** | Now uses new split approach |

---

## Updated Workflow in complete_startup.sh

```
Step 6/10: Creating roles in WSO2 IS
  → Runs: app_scripts/setup_roles_only.sh
  → Creates 5 roles via SCIM2

Step 7/10: Registering APIs in WSO2 AM
  → Runs: app_scripts/register_apis.sh

Step 8/10: Deploying APIs to Gateway
  → Runs: app_scripts/deploy_apis_to_gateway.sh

Step 9/10: Registering test users via Registration API  ← NEW!
  → Runs: app_scripts/register_test_users.sh
  → Uses: POST http://localhost:8004/register
  → Registers 5 test users with validation

Step 10/10: Testing WSO2 IS integration
  → Runs: app_scripts/test_wso2is_integration.sh
```

---

## Benefits

### ✅ Separation of Concerns
- **Roles** = Infrastructure (created early)
- **Users** = Application data (registered via API)

### ✅ Uses Modern Registration API
- Goes through proper validation
- Password strength check
- Email validation
- Consistent with production user registration

### ✅ Testable
- Users created same way as production users
- Tests the registration endpoint during setup
- Validates the entire registration flow

### ✅ Flexible
- Can easily add more test users
- Can skip user registration if desired
- Doesn't fail if users already exist

---

## Test Users Registered

All users registered via `/register` endpoint:

| Username | Password | Email | Role |
|----------|----------|-------|------|
| ops_user | OpsUser123! | ops@example.com | ops_users |
| finance | Finance123! | finance@example.com | finance |
| auditor | Auditor123! | auditor@example.com | auditor |
| user | User1234! | user@example.com | user |
| app_admin | AppAdmin123! | appadmin@example.com | app_admin |

---

## Manual Usage

### Create Roles Only
```bash
./app_scripts/setup_roles_only.sh
```

### Register Test Users
```bash
./app_scripts/register_test_users.sh
```

### Register Custom User
```bash
curl -X POST http://localhost:8004/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "myuser",
    "password": "MySecure123!",
    "email": "my@example.com",
    "first_name": "My",
    "last_name": "User",
    "phone": "+12025551234"
  }'
```

---

## Migration Path

### For Fresh Installations
- ✅ **Automatic** - Just run `./complete_startup.sh`
- New scripts are already integrated

### For Existing Installations
1. Roles already exist (no change needed)
2. Users already exist via old script
3. Can register new users via `/register` endpoint
4. Old users continue to work

---

## Backward Compatibility

✅ **Old script still exists**: `setup_is_users_roles.sh`
- Still creates both roles and users
- Can be used if needed
- Not used in `complete_startup.sh` anymore

✅ **Existing users unaffected**
- Users created via old script still work
- Can coexist with new registered users

---

## Production Impact

### On Remote Server Deployment

**Zero changes needed!** Just pull and run:

```bash
git pull
./complete_startup.sh
```

The new approach:
1. Creates roles (Step 6)
2. Deploys APIs (Steps 7-8)
3. Registers test users via API (Step 9)
4. Tests everything (Step 10)

**Test users are created automatically during setup!**

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Role Creation** | SCIM2 | SCIM2 (unchanged) |
| **User Creation** | SCIM2 direct | Registration API ✅ |
| **Validation** | Basic | Full validation ✅ |
| **Setup Steps** | 9 | 10 |
| **Test Coverage** | Roles + Users | Roles + API ✅ |
| **Production Ready** | Yes | Yes ✅ |

---

## Next Steps

The system now:
- ✅ Creates roles during infrastructure setup
- ✅ Registers users via the modern registration API
- ✅ Validates registration workflow automatically
- ✅ Maintains backward compatibility
- ✅ Works perfectly on remote deployment

**Everything is production-ready!** 🚀
