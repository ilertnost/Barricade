package ws

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type FCMClient struct {
	projectID   string
	clientEmail string
	privateKey  *rsa.PrivateKey
	httpClient  *http.Client
}

type serviceAccount struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
}

func NewFCMClient(serviceAccountJSON []byte) (*FCMClient, error) {
	var sa serviceAccount
	if err := json.Unmarshal(serviceAccountJSON, &sa); err != nil {
		return nil, fmt.Errorf("parse service account: %w", err)
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, fmt.Errorf("no private key found in PEM")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse private key: %w", err)
	}
	rsaKey, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("private key is not RSA")
	}
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		Resolver: &net.Resolver{
			PreferGo: true,
			Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
				// Android shell processes can't use system DNS via /etc/resolv.conf.
				// Use Google's public DNS directly.
				d := net.Dialer{Timeout: 5 * time.Second}
				return d.DialContext(ctx, "udp", "8.8.8.8:53")
			},
		},
	}
	return &FCMClient{
		projectID:   sa.ProjectID,
		clientEmail: sa.ClientEmail,
		privateKey:  rsaKey,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				DialContext: dialer.DialContext,
			},
		},
	}, nil
}

func (c *FCMClient) getAccessToken() (string, error) {
	now := time.Now()
	claims := &jwt.RegisteredClaims{
		Issuer:    c.clientEmail,
		Subject:   c.clientEmail,
		Audience:  jwt.ClaimStrings{"https://oauth2.googleapis.com/token"},
		ExpiresAt: jwt.NewNumericDate(now.Add(3600 * time.Second)),
		IssuedAt:  jwt.NewNumericDate(now),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = "" // not required for service accounts
	assertion, err := token.SignedString(c.privateKey)
	if err != nil {
		return "", fmt.Errorf("sign jwt: %w", err)
	}

	body := fmt.Sprintf(
		"grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Ajwt-bearer&assertion=%s",
		assertion,
	)
	resp, err := c.httpClient.Post(
		"https://oauth2.googleapis.com/token",
		"application/x-www-form-urlencoded",
		bytes.NewBufferString(body),
	)
	if err != nil {
		return "", fmt.Errorf("token request: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode token response: %w", err)
	}
	return result.AccessToken, nil
}

type fcmMessage struct {
	Message fcmPayload `json:"message"`
}

type fcmPayload struct {
	Token        string            `json:"token"`
	Data         map[string]string `json:"data"`
	Notification *fcmNotification  `json:"notification,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

func (c *FCMClient) SendCallOffer(fcmToken, channelID, fromID, callerName string) error {
	accessToken, err := c.getAccessToken()
	if err != nil {
		return fmt.Errorf("get access token: %w", err)
	}

	msg := fcmMessage{
		Message: fcmPayload{
			Token: fcmToken,
			Data: map[string]string{
				"type":        "call_offer",
				"channel_id":  channelID,
				"from_id":     fromID,
				"caller_name": callerName,
			},
			Notification: &fcmNotification{
				Title: "Входящий звонок",
				Body:  callerName,
			},
		},
	}
	data, _ := json.Marshal(msg)

	req, err := http.NewRequest(
		"POST",
		fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.projectID),
		bytes.NewReader(data),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+accessToken)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm send: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("fcm error %d", resp.StatusCode)
	}
	return nil
}
