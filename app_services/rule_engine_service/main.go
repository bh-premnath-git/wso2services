package main

import (
	"fmt"
	"os"
	"rule-engine-service/handlers"
	"rule-engine-service/rule_engine"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	log "github.com/sirupsen/logrus"
)

func main() {
	// Configure logging
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	log.SetLevel(log.InfoLevel)

	// Initialize rule engine service
	ruleEngineSvc, err := rule_engine.NewRuleEngineService()
	if err != nil {
		log.Fatalf("Failed to initialize rule engine: %v", err)
	}
	log.Info("Rule engine initialized successfully")

	// Create Fiber app
	app := fiber.New(fiber.Config{
		AppName:      "Rule Engine Service v1.0.0",
		ServerHeader: "RuleEngine",
		ErrorHandler: customErrorHandler,
	})

	// Middleware
	app.Use(recover.New())
	app.Use(logger.New(logger.Config{
		Format: "[${time}] ${status} - ${method} ${path} ${latency}\n",
	}))
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
		AllowMethods: "GET, POST, PUT, DELETE, OPTIONS",
	}))

	// Initialize handlers
	handler := handlers.NewRuleHandler(ruleEngineSvc)

	// Routes
	app.Get("/", handler.Root)
	app.Get("/health", handler.Health)
	app.Post("/evaluate", handler.Evaluate)
	app.Get("/rules", handler.ListRules)

	// Get port from environment or use default
	port := os.Getenv("SERVICE_PORT")
	if port == "" {
		port = "8005"
	}

	// Start server
	log.Infof("Starting Rule Engine Service on port %s", port)
	if err := app.Listen(fmt.Sprintf(":%s", port)); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func customErrorHandler(c *fiber.Ctx, err error) error {
	code := fiber.StatusInternalServerError
	message := "Internal Server Error"

	if e, ok := err.(*fiber.Error); ok {
		code = e.Code
		message = e.Message
	}

	log.WithFields(log.Fields{
		"error":  err.Error(),
		"status": code,
		"path":   c.Path(),
	}).Error("Request error")

	return c.Status(code).JSON(fiber.Map{
		"error":   message,
		"status":  code,
		"path":    c.Path(),
		"message": err.Error(),
	})
}
