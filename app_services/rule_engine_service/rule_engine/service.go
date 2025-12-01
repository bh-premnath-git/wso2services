package rule_engine

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/hyperjumptech/grule-rule-engine/ast"
	"github.com/hyperjumptech/grule-rule-engine/builder"
	"github.com/hyperjumptech/grule-rule-engine/engine"
	"github.com/hyperjumptech/grule-rule-engine/pkg"
	log "github.com/sirupsen/logrus"
)

var knowledgeLibrary = ast.NewKnowledgeLibrary()

// RuleInput interface for input data
type RuleInput interface {
	DataKey() string
}

// RuleOutput interface for output data
type RuleOutput interface {
	DataKey() string
}

// RuleConfig interface for rule configuration
type RuleConfig interface {
	RuleName() string
	RuleInput() RuleInput
	RuleOutput() RuleOutput
}

// RuleEngineService manages rule execution
type RuleEngineService struct {
	rulesDir string
}

// NewRuleEngineService creates a new rule engine service
func NewRuleEngineService() (*RuleEngineService, error) {
	rulesDir := os.Getenv("RULES_DIR")
	if rulesDir == "" {
		rulesDir = "./rules"
	}

	// Check if rules directory exists
	if _, err := os.Stat(rulesDir); os.IsNotExist(err) {
		return nil, fmt.Errorf("rules directory does not exist: %s", rulesDir)
	}

	svc := &RuleEngineService{
		rulesDir: rulesDir,
	}

	// Build rule engine with all .grl files
	if err := svc.buildRuleEngine(); err != nil {
		return nil, fmt.Errorf("failed to build rule engine: %w", err)
	}

	log.Info("Rule engine service initialized successfully")
	return svc, nil
}

// buildRuleEngine loads all .grl files from the rules directory
func (svc *RuleEngineService) buildRuleEngine() error {
	ruleBuilder := builder.NewRuleBuilder(knowledgeLibrary)

	// Find all .grl files in rules directory
	files, err := filepath.Glob(filepath.Join(svc.rulesDir, "*.grl"))
	if err != nil {
		return fmt.Errorf("failed to find rule files: %w", err)
	}

	if len(files) == 0 {
		return fmt.Errorf("no .grl files found in %s", svc.rulesDir)
	}

	// Load each rule file
	for _, file := range files {
		ruleName := filepath.Base(file)
		log.Infof("Loading rule file: %s", ruleName)

		ruleFile := pkg.NewFileResource(file)
		err := ruleBuilder.BuildRuleFromResource(ruleName, "1.0.0", ruleFile)
		if err != nil {
			return fmt.Errorf("failed to build rule from %s: %w", ruleName, err)
		}

		log.Infof("Successfully loaded rule: %s", ruleName)
	}

	return nil
}

// Execute executes a rule with given configuration
func (svc *RuleEngineService) Execute(ruleConf RuleConfig) error {
	ruleName := ruleConf.RuleName()
	
	// Get knowledge base instance
	knowledgeBase, err := knowledgeLibrary.NewKnowledgeBaseInstance(ruleName, "1.0.0")
	if err != nil {
		return fmt.Errorf("failed to get knowledge base for rule %s: %w", ruleName, err)
	}

	// Create data context
	dataCtx := ast.NewDataContext()

	// Add input data context
	if err := dataCtx.Add(ruleConf.RuleInput().DataKey(), ruleConf.RuleInput()); err != nil {
		return fmt.Errorf("failed to add input data: %w", err)
	}

	// Add output data context
	if err := dataCtx.Add(ruleConf.RuleOutput().DataKey(), ruleConf.RuleOutput()); err != nil {
		return fmt.Errorf("failed to add output data: %w", err)
	}

	// Create rule engine and execute
	ruleEngine := engine.NewGruleEngine()
	if err := ruleEngine.Execute(dataCtx, knowledgeBase); err != nil {
		return fmt.Errorf("rule execution failed: %w", err)
	}

	log.WithFields(log.Fields{
		"rule": ruleName,
	}).Info("Rule executed successfully")

	return nil
}

// ListAvailableRules returns list of available rule files
func (svc *RuleEngineService) ListAvailableRules() ([]string, error) {
	files, err := filepath.Glob(filepath.Join(svc.rulesDir, "*.grl"))
	if err != nil {
		return nil, fmt.Errorf("failed to list rule files: %w", err)
	}

	rules := make([]string, 0, len(files))
	for _, file := range files {
		rules = append(rules, filepath.Base(file))
	}

	return rules, nil
}
