#!/bin/bash

################################################################################
# List all registered users via direct SCIM2 API call
################################################################################

echo "════════════════════════════════════════════════════════════════════"
echo "  Registered Users in WSO2 Identity Server"
echo "════════════════════════════════════════════════════════════════════"
echo ""

# Use Python to call SCIM2 API properly
python3 << 'PYEOF'
import requests
from urllib3 import disable_warnings
from urllib3.exceptions import InsecureRequestWarning

disable_warnings(InsecureRequestWarning)

# Call SCIM2 Users API (using localhost:9444 which maps to wso2is:9443)
response = requests.get(
    'https://localhost:9444/scim2/Users',
    auth=('admin', 'admin'),
    headers={'Accept': 'application/scim+json'},
    verify=False
)

if response.status_code == 200:
    data = response.json()
    users = data.get('Resources', [])
    
    print(f"Total Users: {data.get('totalResults', 0)}\n")
    
    for i, user in enumerate(users, 1):
        username = user.get('userName', 'N/A')
        user_id = user.get('id', 'N/A')[:40]
        
        # Name
        name = user.get('name', {})
        given = name.get('givenName', '')
        family = name.get('familyName', '')
        full_name = f"{given} {family}".strip() or 'N/A'
        
        # Email
        emails = user.get('emails', [])
        email = emails[0].get('value') if emails else 'N/A'
        
        # Phone
        phones = user.get('phoneNumbers', [])
        phone = phones[0].get('value') if phones else 'N/A'
        
        # Address
        addresses = user.get('addresses', [])
        if addresses:
            addr = addresses[0]
            parts = []
            for key in ['streetAddress', 'locality', 'region', 'postalCode', 'country']:
                if addr.get(key):
                    parts.append(addr.get(key))
            address = ', '.join(parts) if parts else 'N/A'
        else:
            address = 'N/A'
        
        print("─" * 70)
        print(f"👤 User #{i}: {username}")
        print("─" * 70)
        print(f"  ID:       {user_id}...")
        print(f"  Name:     {full_name}")
        print(f"  Email:    {email}")
        print(f"  Phone:    {phone}")
        print(f"  Address:  {address}")
        print()
    
    print("=" * 70)
    print(f"\n📊 Summary: {len(users)} users")
    print(f"   With phone: {sum(1 for u in users if u.get('phoneNumbers'))}")
    print(f"   With address: {sum(1 for u in users if u.get('addresses'))}")
else:
    print(f"❌ Error: HTTP {response.status_code}")
    print(response.text[:500])

PYEOF
