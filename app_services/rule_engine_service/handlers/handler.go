package handlers

import (
	"rule-engine-service/rule_engine"

	"github.com/gofiber/fiber/v2"
	log "github.com/sirupsen/logrus"
)

// RuleHandler handles HTTP requests for rule engine
type RuleHandler struct {
	ruleEngine *rule_engine.RuleEngineService
}

// NewRuleHandler creates a new rule handler
func NewRuleHandler(ruleEngine *rule_engine.RuleEngineService) *RuleHandler {
	return &RuleHandler{
		ruleEngine: ruleEngine,
	}
}

// Root handles the root endpoint
func (h *RuleHandler) Root(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"service": "Rule Engine Service",
		"message": "Business rules and compliance API - Golang Edition",
		"version": "1.0.0",
		"engine":  "Grule Rule Engine",
		"endpoints": []string{
			"/health",
			"/evaluate",
			"/rules",
		},
	})
}

// Health handles health check endpoint
func (h *RuleHandler) Health(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"status":  "healthy",
		"service": "rule_engine_service",
		"version": "1.0.0",
		"engine":  "grule",
	})
}

// EvaluateRequest represents the request payload for rule evaluation
type EvaluateRequest struct {
	// Legacy fields for backward compatibility
	TransactionAmount float64 `json:"transaction_amount"`
	TransactionType   string  `json:"transaction_type"`
	UserID            string  `json:"user_id"`
	Country           string  `json:"country"`
	
	// Advanced nested objects (optional)
	User   *rule_engine.UserInfo            `json:"user"`
	Txn    *rule_engine.TransactionMetadata `json:"txn"`
	Device *rule_engine.DeviceInfo          `json:"device"`
}

// EvaluateResponse represents the response from rule evaluation
type EvaluateResponse struct {
	Allowed      bool     `json:"allowed"`
	RulesApplied []string `json:"rules_applied"`
	RiskScore    float64  `json:"risk_score"`
	Message      string   `json:"message"`
}

// Evaluate handles rule evaluation endpoint
func (h *RuleHandler) Evaluate(c *fiber.Ctx) error {
	var req EvaluateRequest
	
	// Parse request body
	if err := c.BodyParser(&req); err != nil {
		log.WithError(err).Error("Failed to parse request body")
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error":   "Invalid request body",
			"message": err.Error(),
		})
	}

	log.WithFields(log.Fields{
		"transaction_amount": req.TransactionAmount,
		"transaction_type":   req.TransactionType,
		"user_id":            req.UserID,
		"country":            req.Country,
	}).Info("Evaluating transaction rules")

	// Create rule context
	ruleContext := rule_engine.NewTransactionRuleContext()
	
	// Populate legacy fields
	ruleContext.TransactionInput.TransactionAmount = req.TransactionAmount
	ruleContext.TransactionInput.TransactionType = req.TransactionType
	ruleContext.TransactionInput.UserID = req.UserID
	ruleContext.TransactionInput.Country = req.Country
	
	// Populate nested User object
	if req.User != nil {
		ruleContext.TransactionInput.User = req.User
	} else {
		// Default user info if not provided
		ruleContext.TransactionInput.User = &rule_engine.UserInfo{
			UserID:           req.UserID,
			KycLevel:         1, // Default basic KYC
			IsBlacklisted:    false,
			Violations:       []string{},
			AccountAgeMonths: 0,
			NoViolation:      true,
			RecentTxnCount:   0,
			IsTrusted:        false,
		}
	}
	
	// Populate nested Transaction metadata
	if req.Txn != nil {
		ruleContext.TransactionInput.Txn = req.Txn
	} else {
		// Map legacy fields to new structure
		ruleContext.TransactionInput.Txn = &rule_engine.TransactionMetadata{
			Amount:     req.TransactionAmount,
			Type:       req.TransactionType,
			Flagged:    false,
			IsHighRisk: false,
			IsHoliday:  false,
		}
	}
	
	// Populate nested Device info
	if req.Device != nil {
		ruleContext.TransactionInput.Device = req.Device
	} else {
		// Default device info
		ruleContext.TransactionInput.Device = &rule_engine.DeviceInfo{
			DeviceCountry: req.Country,
			IPCountry:     req.Country,
			IsVPN:         false,
		}
	}

	// Execute rule engine
	if err := h.ruleEngine.Execute(ruleContext); err != nil {
		log.WithError(err).Error("Rule evaluation failed")
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error":   "Rule evaluation failed",
			"message": err.Error(),
		})
	}

	// Build response
	response := EvaluateResponse{
		Allowed:      ruleContext.TransactionOutput.Allowed,
		RulesApplied: ruleContext.TransactionOutput.RulesApplied,
		RiskScore:    ruleContext.TransactionOutput.RiskScore,
		Message:      ruleContext.TransactionOutput.Message,
	}

	log.WithFields(log.Fields{
		"allowed":       response.Allowed,
		"risk_score":    response.RiskScore,
		"rules_applied": response.RulesApplied,
	}).Info("Rule evaluation completed")

	return c.JSON(response)
}

// RuleInfo represents information about a rule
type RuleInfo struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Type   string `json:"type"`
	Active bool   `json:"active"`
	Path   string `json:"path"`
	Source string `json:"source"`
}

// ListRules handles listing available rules
func (h *RuleHandler) ListRules(c *fiber.Ctx) error {
	ruleFiles, err := h.ruleEngine.ListAvailableRules()
	if err != nil {
		log.WithError(err).Error("Failed to list rules")
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error":   "Failed to list rules",
			"message": err.Error(),
		})
	}

	rules := make([]RuleInfo, 0, len(ruleFiles))
	for _, file := range ruleFiles {
		rules = append(rules, RuleInfo{
			ID:     file,
			Name:   file,
			Type:   "grl",
			Active: true,
			Path:   file,
			Source: "local",
		})
	}

	return c.JSON(fiber.Map{
		"rules":       rules,
		"engine":      "Grule Rule Engine",
		"rule_format": "GRL",
		"mode":        "local",
	})
}
