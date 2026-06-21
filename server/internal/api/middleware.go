package api

import (
	"context"
	"net/http"
	"strings"

	"barricade/internal/auth"
)

func AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tokenStr := r.Header.Get("Authorization")
		if tokenStr == "" {
			tokenStr = r.URL.Query().Get("token")
			if tokenStr != "" {
				tokenStr = "Bearer " + tokenStr
			}
		}
		if tokenStr == "" {
			jsonError(w, "authorization header required", http.StatusUnauthorized)
			return
		}

		parts := strings.SplitN(tokenStr, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			jsonError(w, "invalid authorization format", http.StatusUnauthorized)
			return
		}

		claims, err := auth.ValidateToken(parts[1])
		if err != nil {
			jsonError(w, "invalid or expired token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), "user_id", claims.UserID)
		ctx = context.WithValue(ctx, "username", claims.Username)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
