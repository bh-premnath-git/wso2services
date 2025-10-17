#!/bin/bash

################################################################################
# List all registered users in WSO2 Identity Server
################################################################################

echo "════════════════════════════════════════════════════════════════════"
echo "  WSO2 Identity Server - User List"
echo "════════════════════════════════════════════════════════════════════"
echo ""

# Get users via SCIM2 API (silent curl with follow redirects, only JSON output)
USERS_JSON=$(curl -skL -u admin:admin \
  "https://localhost:9443/scim2/Users" \
  -H "Accept: application/scim+json")

# Parse and display
echo "$USERS_JSON" | jq -r '
  "Total Users: \(.totalResults)\n" +
  (.Resources[] | 
    "────────────────────────────────────────────────────────────────────\n" +
    "👤 Username: \(.userName)\n" +
    "   ID:       \(.id)\n" +
    "   Name:     \(.name.givenName // "N/A") \(.name.familyName // "N/A")\n" +
    "   Email:    \(if .emails then .emails[0].value else "N/A" end)\n" +
    "   Phone:    \(if .phoneNumbers then .phoneNumbers[0].value else "N/A" end)\n" +
    "   Address:  \(if .addresses then 
                    [.addresses[0].streetAddress, .addresses[0].locality, .addresses[0].region, .addresses[0].postalCode, .addresses[0].country] 
                    | map(select(. != null and . != "")) 
                    | join(", ") 
                  else "N/A" end)\n"
  )
'

echo "════════════════════════════════════════════════════════════════════"
echo ""

# Summary
echo "$USERS_JSON" | jq -r '
  "📊 Summary:\n" +
  "   Total users: \(.totalResults)\n" +
  "   With phone: \([.Resources[] | select(.phoneNumbers)] | length)\n" +
  "   With address: \([.Resources[] | select(.addresses)] | length)"
'
echo ""
