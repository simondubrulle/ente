package api

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"golang.org/x/crypto/nacl/box"
)

func TestPushRegistrationBindsRequestSession(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	router := gin.New()
	handler := PushHandler{PushController: &controller.PushController{PushRepo: &repo.PushTokenRepository{DB: db}}}
	router.POST("/push/token", handler.AddToken)
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
		session := fmt.Sprintf("session-%d", id)
		require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(id, ente.Photos, session, "", ""))
		body := fmt.Sprintf(`{"fcmToken":"device", "apnsToken":"apns-%d", "sessionTokenHash":"%s"}`, id, base64.StdEncoding.EncodeToString([]byte("untrusted-session")))
		request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Auth-User-ID", fmt.Sprint(id))
		request.Header.Set("X-Auth-Token", session)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		require.Equal(t, http.StatusOK, response.Code)
		var owner int64
		var apns string
		require.NoError(t, db.QueryRow(`SELECT user_id, apns_token FROM push_tokens WHERE fcm_token = 'device'`).Scan(&owner, &apns))
		require.Equal(t, id, owner)
		require.Equal(t, fmt.Sprintf("apns-%d", id), apns)
	}
	oldHash := auth.HashToken("session-1")
	_, err := (&repo.UserAuthRepository{DB: db}).RemoveTokenByHash(1, oldHash[:])
	require.NoError(t, err)
	for _, session := range []string{"session-1", "session-2"} {
		request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(`{"fcmToken":"device"}`))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Auth-User-ID", "1")
		request.Header.Set("X-Auth-Token", session)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		require.Equal(t, http.StatusUnauthorized, response.Code)
		var owner int64
		require.NoError(t, db.QueryRow(`SELECT user_id FROM push_tokens WHERE fcm_token = 'device'`).Scan(&owner))
		require.Equal(t, int64(2), owner)
	}
	var hash []byte
	require.NoError(t, db.QueryRow(`SELECT session_token_hash FROM push_tokens WHERE fcm_token = 'device'`).Scan(&hash))
	expected := auth.HashToken("session-2")
	require.Equal(t, expected[:], hash)
}

func TestPushRegistrationRejectsInvalidNotificationEnrollment(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "push@example.com", CreationTime: 1})
	require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(1, ente.Photos, "session", "", ""))
	router := gin.New()
	handler := PushHandler{PushController: &controller.PushController{PushRepo: &repo.PushTokenRepository{DB: db}}}
	router.POST("/push/token", handler.AddToken)
	key := base64.StdEncoding.EncodeToString(append([]byte{9}, make([]byte, 31)...))
	for _, fields := range []string{
		`"platform":"web"`,
		`"platform":null`,
		`"notification":{}`,
		fmt.Sprintf(`"notification":{"version":2,"publicKey":"%s"}`, key),
		`"notification":{"version":1,"publicKey":"invalid"}`,
		`"notification":{"version":1,"publicKey":"AQ=="}`,
		fmt.Sprintf(`"notification":{"version":1,"publicKey":"%s"}`, base64.StdEncoding.EncodeToString(make([]byte, 32))),
		fmt.Sprintf(`"platform":"android","notification":{"version":1,"publicKey":"%s"}`, key),
	} {
		t.Run(fields, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(`{"fcmToken":"device",`+fields+`}`))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-Auth-User-ID", "1")
			request.Header.Set("X-Auth-Token", "session")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, http.StatusBadRequest, response.Code, response.Body.String())
		})
	}
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Zero(t, count)
}

func TestPushNotificationRegistrationLifecycle(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	authRepo := &repo.UserAuthRepository{DB: db}
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
		require.NoError(t, authRepo.AddToken(id, ente.Photos, fmt.Sprintf("session-%d", id), "", ""))
	}
	firstKey, _, err := box.GenerateKey(rand.Reader)
	require.NoError(t, err)
	secondKey, _, err := box.GenerateKey(rand.Reader)
	require.NoError(t, err)
	router := gin.New()
	handler := PushHandler{PushController: &controller.PushController{PushRepo: &repo.PushTokenRepository{DB: db}}}
	router.POST("/push/token", handler.AddToken)
	for _, tc := range []struct {
		name     string
		userID   int64
		platform string
		key      []byte
		omit     bool
	}{
		{"old client", 1, "", nil, true},
		{"enroll", 1, "ios", firstKey[:], false},
		{"replace key", 1, "ios", secondKey[:], false},
		{"unenroll", 1, "ios", nil, false},
		{"enroll again", 1, "ios", firstKey[:], false},
		{"switch account", 2, "ios", secondKey[:], false},
		{"omitted enrollment clears key", 2, "android", nil, true},
		{"enroll before logout", 2, "ios", secondKey[:], false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			body := map[string]any{"fcmToken": "device", "apnsToken": "apns"}
			if tc.platform != "" {
				body["platform"] = tc.platform
			}
			if !tc.omit {
				body["notification"] = nil
				if tc.key != nil {
					body["notification"] = map[string]any{"version": 1, "publicKey": tc.key}
				}
			}
			encoded, err := json.Marshal(body)
			require.NoError(t, err)
			request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(string(encoded)))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-Auth-User-ID", fmt.Sprint(tc.userID))
			session := fmt.Sprintf("session-%d", tc.userID)
			request.Header.Set("X-Auth-Token", session)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, http.StatusOK, response.Code, response.Body.String())
			var userID int64
			var platform string
			var key, hash []byte
			require.NoError(t, db.QueryRow(`SELECT user_id, platform, notification_public_key, session_token_hash FROM push_tokens WHERE fcm_token='device'`).Scan(&userID, &platform, &key, &hash))
			require.Equal(t, tc.userID, userID)
			wantPlatform := tc.platform
			if wantPlatform == "" {
				wantPlatform = "ios"
			}
			require.Equal(t, wantPlatform, platform)
			require.Equal(t, tc.key, key)
			expected := auth.HashToken(session)
			require.Equal(t, expected[:], hash)
		})
	}
	hash := auth.HashToken("session-2")
	_, err = authRepo.RemoveTokenByHash(2, hash[:])
	require.NoError(t, err)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Zero(t, count)
}
