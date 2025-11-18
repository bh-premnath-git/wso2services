from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import os
import sys
import logging
import zen
import httpx
import json

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from middleware import add_cors_middleware

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Rule Engine Service",
    version="1.0.0",
    description="Business rules and compliance engine with ZEN Engine BRE"
)

add_cors_middleware(app)

# BRMS Configuration
BRMS_ENABLED = os.getenv("BRMS_ENABLED", "false").lower() == "true"
BRMS_URL = os.getenv("BRMS_URL", "http://brms:80")
BRMS_PROJECT_ID = os.getenv("BRMS_PROJECT_ID", "")
BRMS_TOKEN = os.getenv("BRMS_TOKEN", "")

# Local file fallback
RULES_DIR = os.path.join(os.path.dirname(__file__), '..', 'rules')

if BRMS_ENABLED:
    logger.info(f"BRMS integration enabled - URL: {BRMS_URL}, Project: {BRMS_PROJECT_ID}")
    if not BRMS_PROJECT_ID or not BRMS_TOKEN:
        logger.warning("BRMS_PROJECT_ID or BRMS_TOKEN not set - falling back to local files")
        BRMS_ENABLED = False
else:
    logger.info("Using local file-based rules (BRMS disabled)")

def rule_loader(key: str) -> str:
    """Load JDM rule files from the rules directory"""
    rule_path = os.path.join(RULES_DIR, key)
    try:
        with open(rule_path, 'r') as f:
            content = f.read()
            logger.info(f"Loaded rule: {key}")
            return content
    except FileNotFoundError:
        logger.error(f"Rule file not found: {key}")
        raise
    except Exception as e:
        logger.error(f"Error loading rule {key}: {str(e)}")
        raise

# Initialize engine with loader (for local mode)
engine = zen.ZenEngine({"loader": rule_loader}) if not BRMS_ENABLED else None
if engine:
    logger.info("ZEN Engine initialized successfully (local mode)")


class RuleRequest(BaseModel):
    transaction_amount: float
    transaction_type: str
    user_id: str
    country: str


class RuleResponse(BaseModel):
    allowed: bool
    rules_applied: List[str]
    risk_score: float
    message: str


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "rule_engine_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Rule Engine Service",
        "message": "Business rules and compliance API",
        "endpoints": ["/health", "/evaluate", "/rules"]
    }


@app.post("/evaluate", response_model=RuleResponse)
async def evaluate_rules(request: RuleRequest):
    """Evaluate business rules for a transaction using BRMS or ZEN Engine"""
    try:
        # Prepare input context for the rule engine
        input_context = {
            "transaction_amount": request.transaction_amount,
            "transaction_type": request.transaction_type,
            "user_id": request.user_id,
            "country": request.country
        }
        
        logger.info(f"Evaluating rules for transaction: {input_context}")
        
        if BRMS_ENABLED:
            # Call BRMS API
            result = await evaluate_with_brms("transaction_rules", input_context)
        else:
            # Use local ZEN Engine
            result = engine.evaluate("transaction_rules.json", input_context)
        
        logger.info(f"Rule evaluation result: {result}")
        
        # Extract results from the decision output
        return RuleResponse(
            allowed=result.get("allowed", False),
            rules_applied=result.get("rules_applied", []),
            risk_score=result.get("risk_score", 0.0),
            message=result.get("message", "Evaluation completed")
        )
    except FileNotFoundError as e:
        logger.error(f"Rule file not found: {str(e)}")
        raise HTTPException(status_code=500, detail="Rule configuration error")
    except Exception as e:
        logger.error(f"Error during rule evaluation: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Rule evaluation failed: {str(e)}")


async def evaluate_with_brms(document_path: str, context: Dict[str, Any]) -> Dict[str, Any]:
    """Evaluate rules using BRMS API"""
    url = f"{BRMS_URL}/api/projects/{BRMS_PROJECT_ID}/evaluate/{document_path}"
    headers = {
        "Authorization": f"Bearer {BRMS_TOKEN}",
        "Content-Type": "application/json"
    }
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=context, headers=headers)
            response.raise_for_status()
            result = response.json()
            logger.info(f"BRMS evaluation successful for {document_path}")
            return result
    except httpx.HTTPStatusError as e:
        logger.error(f"BRMS API error: {e.response.status_code} - {e.response.text}")
        raise HTTPException(status_code=502, detail=f"BRMS API error: {e.response.status_code}")
    except Exception as e:
        logger.error(f"BRMS communication error: {str(e)}")
        raise HTTPException(status_code=502, detail=f"BRMS communication failed: {str(e)}")


@app.get("/rules")
async def list_rules():
    """List all available JDM rule files"""
    try:
        rules = []
        
        if BRMS_ENABLED:
            # Fetch rules from BRMS API
            url = f"{BRMS_URL}/api/projects/{BRMS_PROJECT_ID}/documents"
            headers = {"Authorization": f"Bearer {BRMS_TOKEN}"}
            
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(url, headers=headers)
                response.raise_for_status()
                documents = response.json()
                
                for doc in documents:
                    rules.append({
                        "id": doc.get("id"),
                        "name": doc.get("name", doc.get("id")),
                        "type": "jdm",
                        "active": True,
                        "path": doc.get("path", ""),
                        "source": "brms"
                    })
            
            return {
                "rules": rules,
                "engine": "BRMS (GoRules)",
                "rule_format": "JDM",
                "mode": "brms",
                "brms_url": BRMS_URL,
                "project_id": BRMS_PROJECT_ID
            }
        else:
            # List local files
            if os.path.exists(RULES_DIR):
                for filename in os.listdir(RULES_DIR):
                    if filename.endswith('.json'):
                        rules.append({
                            "id": filename,
                            "name": filename.replace('.json', '').replace('_', ' ').title(),
                            "type": "jdm",
                            "active": True,
                            "path": filename,
                            "source": "local"
                        })
            
            return {
                "rules": rules,
                "engine": "ZEN Engine (BRE)",
                "rule_format": "JDM",
                "mode": "local"
            }
    except Exception as e:
        logger.error(f"Error listing rules: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to list rules")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8005)