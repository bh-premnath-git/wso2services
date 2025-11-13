# Rule Engine Service - ZEN Engine BRE Implementation

## Overview

This service implements a **Business Rules Engine (BRE)** using the ZEN Engine Python library. It evaluates transaction rules using JSON Decision Models (JDM) for flexible, externalized business logic.

## Architecture: BRE vs BRMS

### Current Implementation: **BRE (Business Rules Engine)**

✅ **Embeddable**: ZEN Engine integrated directly into the Python service  
✅ **JDM Support**: Rules defined as JSON Decision Model files  
✅ **Decision Tables**: Table-based rule evaluation with hit policies  
✅ **Expression Engine**: ZEN Expression Language for conditions  
✅ **Lightweight**: No separate UI or database required  
✅ **File-based**: Rules stored as JSON files in `/rules` directory  

### Not Implemented: BRMS (Full Management System)

❌ Centralized repository with database  
❌ Web UI for rule management  
❌ Version control and release management  
❌ User authentication for rule editing  
❌ Multi-environment promotion  

## Key Components

### 1. ZEN Engine Integration

**File**: `app/main.py`

```python
import zen

# Initialize engine with custom loader
engine = zen.ZenEngine({"loader": rule_loader})

# Evaluate rules
result = engine.evaluate("transaction_rules.json", input_context)
```

### 2. JDM Rule Files

**Location**: `/rules` directory

- `transaction_rules.json` - Main transaction validation logic
- `risk_assessment.json` - Risk scoring calculations

### 3. Decision Table Features

**transaction_rules.json** implements:

- **Hit Policy**: First-match rule evaluation
- **Inputs**: Amount, Country, Transaction Type
- **Outputs**: Allowed, Risk Score, Message, Rules Applied
- **Rules**:
  - High-risk country blocking (IR, KP, SY)
  - Large transaction thresholds (>100k requires verification)
  - Withdrawal limits (>50k)
  - Country-based risk tiers
  - Default approval logic

### 4. Expression-Based Rules

**risk_assessment.json** demonstrates:

- Dynamic risk score calculation
- Conditional expressions
- Mathematical operations
- Risk level categorization

## API Endpoints

### POST /evaluate
Evaluate transaction against business rules

**Request**:
```json
{
  "transaction_amount": 15000,
  "transaction_type": "transfer",
  "user_id": "user_123",
  "country": "US"
}
```

**Response**:
```json
{
  "allowed": true,
  "rules_applied": ["amount_limit", "country_check", "kyc_verification"],
  "risk_score": 0.2,
  "message": "Transaction approved"
}
```

### GET /rules
List all available JDM rule files

**Response**:
```json
{
  "rules": [
    {
      "id": "transaction_rules.json",
      "name": "Transaction Rules",
      "type": "jdm",
      "active": true,
      "path": "transaction_rules.json"
    }
  ],
  "engine": "ZEN Engine (BRE)",
  "rule_format": "JDM"
}
```

### GET /health
Service health check

## Rule Management

### Adding New Rules

1. Create JDM file in `/rules` directory
2. Define decision graph with nodes and edges
3. Service automatically loads rules via `rule_loader()`

### Modifying Existing Rules

1. Edit JDM JSON file directly
2. Restart service to reload rules
3. No code changes required

### Rule File Structure

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    {
      "id": "request",
      "type": "inputNode"
    },
    {
      "id": "decision_table",
      "type": "decisionTableNode",
      "content": {
        "hitPolicy": "first",
        "inputs": [...],
        "outputs": [...],
        "rules": [...]
      }
    },
    {
      "id": "response",
      "type": "outputNode"
    }
  ],
  "edges": [...]
}
```

## Testing

### Example Test Cases

**Case 1: Standard Transaction (Approved)**
```bash
curl -X POST http://localhost:8005/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 5000,
    "transaction_type": "transfer",
    "user_id": "user_123",
    "country": "US"
  }'
```

Expected: `{"allowed": true, "risk_score": 0.2}`

**Case 2: High-Risk Country (Blocked)**
```bash
curl -X POST http://localhost:8005/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 1000,
    "transaction_type": "transfer",
    "user_id": "user_456",
    "country": "IR"
  }'
```

Expected: `{"allowed": false, "risk_score": 1.0}`

**Case 3: Large Transaction (Requires Verification)**
```bash
curl -X POST http://localhost:8005/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_amount": 150000,
    "transaction_type": "transfer",
    "user_id": "user_789",
    "country": "US"
  }'
```

Expected: `{"allowed": false, "risk_score": 0.9}`

## Dependencies

- `zen-engine>=0.11.0` - Core BRE library
- `fastapi>=0.119.0` - Web framework
- `uvicorn[standard]>=0.32.0` - ASGI server

## Deployment

### Docker Build

```bash
cd /home/premnath/application
docker-compose build rule-engine-service
```

### Run Service

```bash
docker-compose up rule-engine-service
```

Service available at: `http://localhost:8005`

## Advantages of BRE Approach

1. **Decoupled Logic**: Business rules separate from application code
2. **No Redeployment**: Rule changes without code changes
3. **Transparent**: JDM files are human-readable JSON
4. **Testable**: Rules can be unit tested independently
5. **Lightweight**: No additional infrastructure required
6. **Version Control**: JDM files tracked in Git
7. **Fast Evaluation**: Rust-based engine core

## Migration Path to BRMS

If centralized management is needed in the future:

1. Deploy GoRules BRMS as separate service
2. Migrate JDM files to BRMS repository
3. Update service to fetch rules via BRMS API
4. Add UI access for business users
5. Implement versioning and approvals

Current BRE implementation provides foundation for this upgrade.

## References

- [ZEN Engine Documentation](https://gorules.io/docs/user-guide/decision-modeling/overview)
- [JDM Specification](https://gorules.io/docs/user-guide/decision-modeling/jdm)
- [ZEN Expression Language](https://gorules.io/docs/user-guide/zen-engine/expression-language)
