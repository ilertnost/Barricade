package ws

import (
	"encoding/json"
	"time"

	"github.com/gorilla/websocket"
)

const (
	pongWait   = 60 * time.Second
	pingPeriod = 30 * time.Second
	writeWait  = 10 * time.Second
)

type Client struct {
	UserID      string
	Username    string
	DisplayName string
	Hub         *Hub
	Conn        *websocket.Conn
	Send        chan []byte
}

func NewClient(hub *Hub, conn *websocket.Conn, userID, username, displayName string) *Client {
	return &Client{
		UserID:      userID,
		Username:    username,
		DisplayName: displayName,
		Hub:         hub,
		Conn:        conn,
		Send:        make(chan []byte, 256),
	}
}

func (c *Client) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, msgBytes, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		c.Hub.handleMessage(c, msgBytes)
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.Conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) SendJSON(v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		c.SendError("marshal error")
		return
	}
	c.Send <- data
}

func (c *Client) SendError(msg string) {
	data, _ := json.Marshal(OutgoingMessage{
		Type:    "error",
		Payload: map[string]string{"message": msg},
	})
	c.Send <- data
}
