package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"barricade/internal/api"
	"barricade/internal/auth"
	"barricade/internal/db"
	"barricade/internal/file"
	"barricade/internal/ws"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	dataDir := os.Getenv("DATA_DIR")
	if dataDir == "" {
		dataDir = "./data"
	}

	os.MkdirAll(dataDir, 0755)

	database, err := db.New(filepath.Join(dataDir, "messenger.db"))
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	store, err := file.NewStore(filepath.Join(dataDir, "files"))
	if err != nil {
		log.Fatalf("file store: %v", err)
	}
	hub := ws.NewHub(database)
	go hub.Run()

	router := api.NewRouter(database, store, hub)
	mux := http.NewServeMux()
	mux.Handle("/", router)

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		tokenStr := r.URL.Query().Get("token")
		if tokenStr == "" {
			http.Error(w, "token required", http.StatusUnauthorized)
			return
		}
		claims, err := auth.ValidateToken(tokenStr)
		if err != nil {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("ws upgrade: %v", err)
			return
		}
		client := ws.NewClient(hub, conn, claims.UserID, claims.Username, claims.DisplayName)
		hub.Register <- client
		go client.WritePump()
		go client.ReadPump()
	})

	log.Printf("server starting on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server: %v", err)
	}
}
