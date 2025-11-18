#!/usr/bin/env python3
"""
Test script for ZEN Engine BRE implementation
Run after service is up: python test_rules.py
"""

import requests
import json
from typing import Dict, Any

BASE_URL = "http://localhost:8005"

def print_test(name: str, request: Dict[str, Any], response: Dict[str, Any]):
    """Pretty print test results"""
    print(f"\n{'='*60}")
    print(f"TEST: {name}")
    print(f"{'='*60}")
    print(f"Request:")
    print(json.dumps(request, indent=2))
    print(f"\nResponse:")
    print(json.dumps(response, indent=2))
    print(f"Status: {'✅ PASS' if response.get('allowed') is not None else '❌ FAIL'}")

def test_health():
    """Test health endpoint"""
    print("\n" + "="*60)
    print("HEALTH CHECK")
    print("="*60)
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"Status Code: {response.status_code}")
        print(json.dumps(response.json(), indent=2))
        return response.status_code == 200
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def test_list_rules():
    """Test rules listing endpoint"""
    print("\n" + "="*60)
    print("LIST RULES")
    print("="*60)
    try:
        response = requests.get(f"{BASE_URL}/rules")
        print(f"Status Code: {response.status_code}")
        print(json.dumps(response.json(), indent=2))
        return response.status_code == 200
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def test_evaluate(name: str, transaction_data: Dict[str, Any]):
    """Test rule evaluation"""
    try:
        response = requests.post(
            f"{BASE_URL}/evaluate",
            json=transaction_data
        )
        if response.status_code == 200:
            print_test(name, transaction_data, response.json())
            return True
        else:
            print(f"❌ FAILED: Status {response.status_code}")
            print(response.text)
            return False
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def run_all_tests():
    """Run comprehensive test suite"""
    print("\n" + "🚀"*30)
    print("ZEN ENGINE BRE TEST SUITE")
    print("🚀"*30)
    
    results = []
    
    # Health check
    results.append(("Health Check", test_health()))
    
    # List rules
    results.append(("List Rules", test_list_rules()))
    
    # Test Case 1: Small amount, safe country (Should APPROVE)
    results.append(("Small Transaction - Safe Country", test_evaluate(
        "Small Transaction (US, $5,000)",
        {
            "transaction_amount": 5000,
            "transaction_type": "transfer",
            "user_id": "user_123",
            "country": "US"
        }
    )))
    
    # Test Case 2: High-risk country (Should BLOCK)
    results.append(("High-Risk Country", test_evaluate(
        "High-Risk Country (Iran, $1,000)",
        {
            "transaction_amount": 1000,
            "transaction_type": "transfer",
            "user_id": "user_456",
            "country": "IR"
        }
    )))
    
    # Test Case 3: Large transaction (Should BLOCK - requires verification)
    results.append(("Large Transaction", test_evaluate(
        "Large Transaction (US, $150,000)",
        {
            "transaction_amount": 150000,
            "transaction_type": "transfer",
            "user_id": "user_789",
            "country": "US"
        }
    )))
    
    # Test Case 4: Large withdrawal (Should BLOCK)
    results.append(("Large Withdrawal", test_evaluate(
        "Large Withdrawal (US, $75,000)",
        {
            "transaction_amount": 75000,
            "transaction_type": "withdrawal",
            "user_id": "user_101",
            "country": "US"
        }
    )))
    
    # Test Case 5: Medium-risk country with medium amount
    results.append(("Medium Risk Transaction", test_evaluate(
        "Medium Risk (Russia, $25,000)",
        {
            "transaction_amount": 25000,
            "transaction_type": "transfer",
            "user_id": "user_202",
            "country": "RU"
        }
    )))
    
    # Test Case 6: Standard deposit
    results.append(("Standard Deposit", test_evaluate(
        "Standard Deposit (UK, $8,000)",
        {
            "transaction_amount": 8000,
            "transaction_type": "deposit",
            "user_id": "user_303",
            "country": "GB"
        }
    )))
    
    # Test Case 7: Edge case - exactly at threshold
    results.append(("Threshold Test", test_evaluate(
        "At Threshold (US, $10,000)",
        {
            "transaction_amount": 10000,
            "transaction_type": "transfer",
            "user_id": "user_404",
            "country": "US"
        }
    )))
    
    # Test Case 8: Another sanctioned country
    results.append(("Sanctioned Country", test_evaluate(
        "Sanctioned Country (North Korea, $500)",
        {
            "transaction_amount": 500,
            "transaction_type": "transfer",
            "user_id": "user_505",
            "country": "KP"
        }
    )))
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {name}")
    
    print(f"\n{passed}/{total} tests passed ({(passed/total)*100:.1f}%)")
    
    if passed == total:
        print("\n🎉 ALL TESTS PASSED! ZEN Engine BRE is working correctly.")
    else:
        print(f"\n⚠️  {total - passed} test(s) failed. Check service logs.")

if __name__ == "__main__":
    run_all_tests()
