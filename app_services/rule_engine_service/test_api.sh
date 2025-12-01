#!/bin/bash

# ========================================================================
# PRODUCTION-GRADE gRULE TEST SCRIPT
# Showcasing: Nested objects, chaining, velocity, KYC tiers, geo risk
# Focus: USA, UK, Canada, India, UAE
# ========================================================================

BASE_URL="http://localhost:8005"

echo "========================================================================"
echo "🚀 PRODUCTION-GRADE gRULE ENGINE - COMPREHENSIVE API TESTS"
echo "Focus Countries: USA 🇺🇸 | UK 🇬🇧 | Canada 🇨🇦 | India 🇮🇳 | UAE 🇦🇪"
echo "========================================================================"
echo ""

# Test 1: Health Check
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: Health Check & Service Info"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s "$BASE_URL/health" | jq '.'
echo ""

# Test 2: List Rules
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: List Available Production Rules"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s "$BASE_URL/rules" | jq '.'
echo ""

# ========================================================================
# TIER 1: HARD BLOCKS
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: HARD BLOCK - Blacklisted User (USA)"
echo "Expected: ❌ BLOCKED - Account suspended"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "US",
    "user": {
      "user_id": "usr_blacklisted",
      "kyc_level": 2,
      "is_blacklisted": true,
      "violations": [],
      "account_age_months": 6,
      "no_violation": false,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 5000,
      "type": "transfer"
    },
    "device": {
      "device_country": "US",
      "ip_country": "US",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: HARD BLOCK - Fraud History (UK)"
echo "Expected: ❌ BLOCKED - Fraud history detected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "GB",
    "user": {
      "user_id": "usr_fraud",
      "kyc_level": 1,
      "is_blacklisted": false,
      "violations": ["fraud", "chargeback"],
      "account_age_months": 3,
      "no_violation": false,
      "recent_txn_count": 2
    },
    "txn": {
      "amount": 8000,
      "type": "deposit"
    },
    "device": {
      "device_country": "GB",
      "ip_country": "GB",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 5: HARD BLOCK - Sanctioned Country (Iran)"
echo "Expected: ❌ BLOCKED - Sanctioned country"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 2000,
    "transaction_type": "transfer",
    "user_id": "usr001",
    "country": "IR"
  }' | jq '.'
echo ""

# ========================================================================
# TIER 2: TRUSTED USER FAST PASS
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 6: FAST PASS - Premium Trusted User (Canada)"
echo "Expected: ✅ APPROVED - FastPass (KYC 3, 18mo account, no violations)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "CA",
    "user": {
      "user_id": "usr_premium",
      "kyc_level": 3,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 18,
      "no_violation": true,
      "recent_txn_count": 2,
      "is_trusted": true
    },
    "txn": {
      "amount": 18000,
      "type": "transfer"
    },
    "device": {
      "device_country": "CA",
      "ip_country": "CA",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

# ========================================================================
# TIER 3: GEOGRAPHIC & DEVICE RISK
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 7: DEVICE MISMATCH - USA transaction from UAE device"
echo "Expected: ❌ BLOCKED - Device-country mismatch"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "US",
    "user": {
      "user_id": "usr_traveler",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 8,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 12000,
      "type": "withdrawal"
    },
    "device": {
      "device_country": "AE",
      "ip_country": "AE",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 8: VPN RISK - High-value transaction via VPN (India)"
echo "Expected: ❌ BLOCKED - VPN detected on high-value transaction"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "IN",
    "user": {
      "user_id": "usr_vpn",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 5,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 15000,
      "type": "transfer"
    },
    "device": {
      "device_country": "IN",
      "ip_country": "IN",
      "is_vpn": true
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 9: LOW RISK GEO - Standard USA Transaction"
echo "Expected: ✅ APPROVED - Low risk country (US, amount: $35k)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "US",
    "user": {
      "user_id": "usr_normal",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 6,
      "no_violation": true,
      "recent_txn_count": 2
    },
    "txn": {
      "amount": 35000,
      "type": "deposit"
    },
    "device": {
      "device_country": "US",
      "ip_country": "US",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 10: MEDIUM-LOW RISK GEO - UAE Transaction (KYC 2)"
echo "Expected: ✅ APPROVED - Enhanced monitoring (UAE, amount: $28k)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "AE",
    "user": {
      "user_id": "usr_uae",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 4,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 28000,
      "type": "payment"
    },
    "device": {
      "device_country": "AE",
      "ip_country": "AE",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

# ========================================================================
# TIER 4: BEHAVIORAL & VELOCITY
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 11: VELOCITY CHECK - Rapid-fire transactions (UK)"
echo "Expected: ❌ BLOCKED - Suspicious velocity (>5 txns in 10 mins)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "GB",
    "user": {
      "user_id": "usr_rapid",
      "kyc_level": 1,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 2,
      "no_violation": true,
      "recent_txn_count": 8
    },
    "txn": {
      "amount": 3000,
      "type": "transfer"
    },
    "device": {
      "device_country": "GB",
      "ip_country": "GB",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 12: CHARGEBACK HISTORY - User with past chargebacks (India)"
echo "Expected: ❌ BLOCKED - Manual review required"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "IN",
    "user": {
      "user_id": "usr_chargeback",
      "kyc_level": 1,
      "is_blacklisted": false,
      "violations": ["chargeback"],
      "account_age_months": 4,
      "no_violation": false,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 5000,
      "type": "withdrawal"
    },
    "device": {
      "device_country": "IN",
      "ip_country": "IN",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

# ========================================================================
# TIER 5: KYC-BASED RULES
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 13: NO KYC LIMIT - User with no KYC (Canada)"
echo "Expected: ❌ BLOCKED - Complete KYC to proceed (>$1000)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "CA",
    "user": {
      "user_id": "usr_no_kyc",
      "kyc_level": 0,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 1,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 1500,
      "type": "transfer"
    },
    "device": {
      "device_country": "CA",
      "ip_country": "CA",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 14: BASIC KYC LIMIT - User with KYC Level 1 (UAE)"
echo "Expected: ❌ BLOCKED - Upgrade to verified KYC (>$10k)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "AE",
    "user": {
      "user_id": "usr_basic_kyc",
      "kyc_level": 1,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 3,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 12000,
      "type": "deposit"
    },
    "device": {
      "device_country": "AE",
      "ip_country": "AE",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

# ========================================================================
# TIER 6: TRANSACTION TYPE & CHAINING
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 15: RULE CHAINING - Large Transaction Flagging (USA, $75k)"
echo "Expected: ❌ BLOCKED - Manager approval (flagged then reviewed)"
echo "Rule Chain: FlagLargeTransaction → FlaggedTransactionReview"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "US",
    "user": {
      "user_id": "usr_big_txn",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 10,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 75000,
      "type": "transfer"
    },
    "device": {
      "device_country": "US",
      "ip_country": "US",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 16: CRYPTO TRANSACTION - High risk crypto (UK, $8k)"
echo "Expected: ❌ BLOCKED - Crypto requires compliance review"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "GB",
    "user": {
      "user_id": "usr_crypto",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 5,
      "no_violation": true,
      "recent_txn_count": 2
    },
    "txn": {
      "amount": 8000,
      "type": "crypto"
    },
    "device": {
      "device_country": "GB",
      "ip_country": "GB",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 17: LARGE WITHDRAWAL - High-value withdrawal (India, $65k)"
echo "Expected: ❌ BLOCKED - Large withdrawal requires verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "IN",
    "user": {
      "user_id": "usr_withdraw",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 8,
      "no_violation": true,
      "recent_txn_count": 1
    },
    "txn": {
      "amount": 65000,
      "type": "withdrawal"
    },
    "device": {
      "device_country": "IN",
      "ip_country": "IN",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

# ========================================================================
# TIER 7-8: STANDARD & MONITORING
# ========================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 18: STANDARD APPROVAL - Low-risk transaction (Canada, $3k)"
echo "Expected: ✅ APPROVED - Standard approval"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "CA",
    "user": {
      "user_id": "usr_standard",
      "kyc_level": 1,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 4,
      "no_violation": true,
      "recent_txn_count": 2
    },
    "txn": {
      "amount": 3000,
      "type": "payment"
    },
    "device": {
      "device_country": "CA",
      "ip_country": "CA",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 19: BACKWARD COMPATIBILITY - Legacy API format (USA)"
echo "Expected: ✅ APPROVED - Works with old API structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 4500,
    "transaction_type": "deposit",
    "user_id": "usr_legacy",
    "country": "US"
  }' | jq '.'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 20: MEDIUM AMOUNT MONITORING - Mid-range (UK, $18k)"
echo "Expected: ✅ APPROVED - With monitoring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s -X POST "$BASE_URL/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "country": "GB",
    "user": {
      "user_id": "usr_medium",
      "kyc_level": 2,
      "is_blacklisted": false,
      "violations": [],
      "account_age_months": 7,
      "no_violation": true,
      "recent_txn_count": 3
    },
    "txn": {
      "amount": 18000,
      "type": "transfer"
    },
    "device": {
      "device_country": "GB",
      "ip_country": "GB",
      "is_vpn": false
    }
  }' | jq '.'
echo ""

echo "========================================================================"
echo "✅ ALL 20 PRODUCTION-GRADE gRULE TESTS COMPLETED!"
echo ""
echo "Features Demonstrated:"
echo "  ✓ Nested objects (User, Transaction, Device)"
echo "  ✓ List matching (Violations.Contains)"
echo "  ✓ Rule chaining (Flagged → Review)"
echo "  ✓ Salience-based conflict resolution"
echo "  ✓ KYC tier enforcement"
echo "  ✓ Geographic risk scoring (US/UK/CA/IN/AE)"
echo "  ✓ Velocity checks"
echo "  ✓ Device-country mismatch detection"
echo "  ✓ Backward compatibility"
echo "  ✓ Complex conditions (&&, ||, In())"
echo "========================================================================"
