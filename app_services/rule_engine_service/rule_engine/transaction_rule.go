package rule_engine

// TransactionRuleContext holds the context for transaction rule evaluation
type TransactionRuleContext struct {
	TransactionInput  *TransactionInput
	TransactionOutput *TransactionOutput
}

func (trc *TransactionRuleContext) RuleName() string {
	return "transaction_rules.grl"
}

func (trc *TransactionRuleContext) RuleInput() RuleInput {
	return trc.TransactionInput
}

func (trc *TransactionRuleContext) RuleOutput() RuleOutput {
	return trc.TransactionOutput
}

// UserInfo represents user-level data for rule evaluation
type UserInfo struct {
	UserID            string   `json:"user_id"`
	KycLevel          int      `json:"kyc_level"`           // 0=none, 1=basic, 2=verified, 3=premium
	IsBlacklisted     bool     `json:"is_blacklisted"`
	Violations        []string `json:"violations"`          // e.g., ["chargeback", "fraud"]
	AccountAgeMonths  int      `json:"account_age_months"`
	NoViolation       bool     `json:"no_violation"`
	RecentTxnCount    int      `json:"recent_txn_count"`    // Count in last 10 mins
	IsTrusted         bool     `json:"is_trusted"`
}

// HasViolation checks if user has a specific violation (helper for gRule)
func (ui *UserInfo) HasViolation(violationType string) bool {
	for _, v := range ui.Violations {
		if v == violationType {
			return true
		}
	}
	return false
}

// TransactionMetadata represents transaction-level metadata
type TransactionMetadata struct {
	Amount     float64 `json:"amount"`
	Type       string  `json:"type"`        // deposit, withdrawal, transfer, payment, crypto
	Flagged    bool    `json:"flagged"`     // Set by rules for chaining
	IsHighRisk bool    `json:"is_high_risk"`
	IsHoliday  bool    `json:"is_holiday"`  // Can be computed or passed in
}

// DeviceInfo represents device and geo information
type DeviceInfo struct {
	DeviceCountry string `json:"device_country"`
	IPCountry     string `json:"ip_country"`
	IsVPN         bool   `json:"is_vpn"`
}

// TransactionInput represents the input data for transaction evaluation
type TransactionInput struct {
	// Legacy fields for backward compatibility
	TransactionAmount float64 `json:"transaction_amount"`
	TransactionType   string  `json:"transaction_type"`
	UserID            string  `json:"user_id"`
	Country           string  `json:"country"`
	
	// Advanced nested objects
	User   *UserInfo            `json:"user"`
	Txn    *TransactionMetadata `json:"txn"`
	Device *DeviceInfo          `json:"device"`
}

func (ti *TransactionInput) DataKey() string {
	return "Input"
}

// TransactionOutput represents the output of transaction evaluation
type TransactionOutput struct {
	Allowed      bool     `json:"allowed"`
	RulesApplied []string `json:"rules_applied"`
	RiskScore    float64  `json:"risk_score"`
	Message      string   `json:"message"`
}

func (to *TransactionOutput) DataKey() string {
	return "Output"
}

// AddRuleApplied adds a rule name to the list of applied rules
func (to *TransactionOutput) AddRuleApplied(ruleName string) {
	to.RulesApplied = append(to.RulesApplied, ruleName)
}

// NewTransactionRuleContext creates a new transaction rule context
func NewTransactionRuleContext() *TransactionRuleContext {
	return &TransactionRuleContext{
		TransactionInput: &TransactionInput{},
		TransactionOutput: &TransactionOutput{
			Allowed:      false,
			RulesApplied: make([]string, 0),
			RiskScore:    0.0,
			Message:      "",
		},
	}
}
