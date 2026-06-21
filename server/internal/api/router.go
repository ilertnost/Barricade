package api

import (
	"net/http"

	"barricade/internal/db"
	"barricade/internal/file"
	"barricade/internal/ws"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
)

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func NewRouter(database *db.DB, store *file.Store, hub *ws.Hub) http.Handler {
	r := chi.NewRouter()
	h := NewHandler(database, store, hub)

	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(corsMiddleware)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok"}`))
	})

	r.Post("/api/auth/register", h.Register)
	r.Post("/api/auth/login", h.Login)
	r.Post("/api/auth/check-device", h.CheckDevice)
	r.Post("/api/auth/reset-password", h.ResetPassword)

	r.Group(func(r chi.Router) {
		r.Use(AuthMiddleware)
		r.Post("/api/auth/change-password", h.ChangePassword)
		r.Get("/api/users/@me", h.Me)
		r.Patch("/api/users/@me", h.UpdateProfile)
		r.Get("/api/users", h.GetUsers)
		r.Get("/api/search", h.SearchAll)
		r.Post("/api/channels", h.CreateChannel)
		r.Get("/api/channels", h.GetChannels)
		r.Patch("/api/channels/{id}/settings", h.UpdateChannelSettings)
		r.Get("/api/channels/{id}/messages", h.GetChannelMessages)
		r.Get("/api/channels/{id}/media", h.GetChannelMedia)
		r.Get("/api/channels/{id}/members", h.GetChannelMembers)
		r.Post("/api/channels/{id}/members", h.AddChannelMember)
		r.Patch("/api/channels/{id}/members/{userId}", h.UpdateChannelMemberRole)
		r.Post("/api/channels/{id}/join", h.JoinChannel)
		r.Post("/api/files/upload", h.UploadFile)
		r.Get("/api/files/{id}", h.GetFile)
		r.Get("/api/files/{id}/info", h.GetFileInfo)
		r.Get("/api/users/{id}", h.GetUser)
		r.Post("/api/fcm/register", h.RegisterFCMToken)
	})
	// DELETE registered with method pattern to avoid chi Group routing issues
	r.With(AuthMiddleware).Delete("/api/channels/{id}", h.DeleteChannel)
	r.With(AuthMiddleware).Delete("/api/channels/{id}/members/{userId}", h.RemoveChannelMember)

	return r
}
