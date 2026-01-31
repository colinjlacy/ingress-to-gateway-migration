package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

var (
	version = getEnv("VERSION", "v1")
	dbHost  = getEnv("DB_HOST", "catalogue-db")
	dbPort  = getEnv("DB_PORT", "3306")
	dbUser  = getEnv("DB_USER", "root")
	dbPass  = getEnv("DB_PASSWORD", "fake_password")
	dbName  = getEnv("DB_NAME", "socksdb")
)

type Response struct {
	Version   string            `json:"version"`
	Timestamp string            `json:"timestamp"`
	Hostname  string            `json:"hostname"`
	Message   string            `json:"message"`
	Headers   map[string]string `json:"headers,omitempty"`
	DBStatus  string            `json:"db_status"`
}

func main() {
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/db-check", handleDBCheck)

	port := getEnv("PORT", "8080")
	log.Printf("Starting version-app %s on port %s", version, port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()

	headers := make(map[string]string)
	for name, values := range r.Header {
		if len(values) > 0 {
			headers[name] = values[0]
		}
	}

	resp := Response{
		Version:   version,
		Timestamp: time.Now().Format(time.RFC3339),
		Hostname:  hostname,
		Message:   fmt.Sprintf("Hello from version %s!", version),
		Headers:   headers,
		DBStatus:  "not checked",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func handleDBCheck(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s", dbUser, dbPass, dbHost, dbPort, dbName)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		respondWithError(w, fmt.Sprintf("Failed to connect to database: %v", err))
		return
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		respondWithError(w, fmt.Sprintf("Failed to ping database: %v", err))
		return
	}

	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM sock").Scan(&count)
	if err != nil {
		respondWithError(w, fmt.Sprintf("Failed to query database: %v", err))
		return
	}

	resp := Response{
		Version:   version,
		Timestamp: time.Now().Format(time.RFC3339),
		Hostname:  hostname,
		Message:   fmt.Sprintf("Successfully connected to MySQL database"),
		DBStatus:  fmt.Sprintf("connected - %d socks in database", count),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func respondWithError(w http.ResponseWriter, message string) {
	resp := Response{
		Version:   version,
		Timestamp: time.Now().Format(time.RFC3339),
		Message:   "Database connection failed",
		DBStatus:  message,
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	json.NewEncoder(w).Encode(resp)
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
