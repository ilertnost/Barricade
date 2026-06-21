// One-off admin tool: reset a user's password by writing a new bcrypt hash.
// Usage: DATA_DIR=/path resetpw <username> <newpassword>
package main

import (
	"database/sql"
	"fmt"
	"os"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Println("usage: resetpw <username> <newpassword>")
		os.Exit(1)
	}
	username, password := os.Args[1], os.Args[2]
	dataDir := os.Getenv("DATA_DIR")
	if dataDir == "" {
		dataDir = "./data"
	}
	db, err := sql.Open("sqlite", dataDir+"/messenger.db?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		fmt.Println("open:", err)
		os.Exit(1)
	}
	defer db.Close()

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		fmt.Println("hash:", err)
		os.Exit(1)
	}
	res, err := db.Exec(`UPDATE users SET password_hash = ? WHERE username = ?`, string(hash), username)
	if err != nil {
		fmt.Println("update:", err)
		os.Exit(1)
	}
	n, _ := res.RowsAffected()
	fmt.Printf("updated %d row(s) for user %q\n", n, username)
}
