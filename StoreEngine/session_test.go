package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestCookieSessionRoundTrip(t *testing.T) {
	u, _ := url.Parse("https://buy.itunes.apple.com/WebObjects/login")
	jar, err := newSessionJar(nil)
	if err != nil {
		t.Fatal(err)
	}
	jar.SetCookies(u, []*http.Cookie{{Name: "session", Value: "test-secret", Domain: ".itunes.apple.com", Path: "/", Secure: true, HttpOnly: true, MaxAge: 3600}})
	encoded, err := json.Marshal(session{Keys: map[string][]byte{}, Cookies: jar.snapshot()})
	if err != nil {
		t.Fatal(err)
	}
	var state session
	if err = json.Unmarshal(encoded, &state); err != nil {
		t.Fatal(err)
	}
	restored, err := newSessionJar(state.Cookies)
	if err != nil {
		t.Fatal(err)
	}
	other, _ := url.Parse("https://auth.itunes.apple.com/auth/v1/native")
	if got := restored.Cookies(other); len(got) != 1 || got[0].Value != "test-secret" {
		t.Fatalf("cookie was not restored: %d", len(got))
	}
	record := restored.snapshot()[0].Cookie
	if record.MaxAge != 0 || record.Expires.After(time.Now().Add(time.Hour+time.Second)) {
		t.Fatal("restoring cookies must not extend expiry")
	}
	logout, _ := url.Parse("https://auth.itunes.apple.com/logout")
	jar.SetCookies(logout, []*http.Cookie{{Name: "session", Domain: "itunes.apple.com", Path: "/", MaxAge: -1}})
	if len(jar.snapshot()) != 0 {
		t.Fatal("deleted cookies must not survive persistence")
	}
}

func TestHostOnlyCookiePreservesDefaultPath(t *testing.T) {
	u, _ := url.Parse("https://buy.itunes.apple.com/WebObjects/login")
	jar, _ := newSessionJar(nil)
	jar.SetCookies(u, []*http.Cookie{{Name: "session", Value: "host-only", Secure: true}})
	restored, _ := newSessionJar(jar.snapshot())
	inside, _ := url.Parse("https://buy.itunes.apple.com/WebObjects/next")
	outside, _ := url.Parse("https://buy.itunes.apple.com/other")
	subdomain, _ := url.Parse("https://sub.buy.itunes.apple.com/WebObjects/next")
	if len(restored.Cookies(inside)) != 1 || len(restored.Cookies(outside)) != 0 || len(restored.Cookies(subdomain)) != 0 {
		t.Fatal("restoring cookies changed their host or default path scope")
	}
}

func TestSeparateAccountsDoNotShareState(t *testing.T) {
	a := session{Keys: map[string][]byte{}}
	b := session{Keys: map[string][]byte{}}
	_ = a.Set("anisette-v4", []byte("account-one"))
	if _, err := b.Get("anisette-v4"); err == nil {
		t.Fatal("account state leaked between stores")
	}
}

func TestAccountResponseDoesNotPersistPassword(t *testing.T) {
	data := []byte(`{"email":"test@example.invalid","password":"never-save-this","storeFront":"143441"}`)
	req := request{Operation: "account", Session: session{Keys: map[string][]byte{"account": data}}}
	result := execute(context.Background(), &req, func(response) {})
	if result.Error != "" {
		t.Fatal(result.Error)
	}
	var saved session
	if err := json.Unmarshal(result.State, &saved); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(saved.Keys["account"]), "never-save-this") {
		t.Fatal("raw Apple password persisted")
	}
	if result.Account == nil || result.Account.Store != "143441" {
		t.Fatal("public account summary missing")
	}
}

func TestMalformedSavedStateFailsClosed(t *testing.T) {
	result := execute(context.Background(), &request{Operation: "login", State: []byte("broken")}, func(response) {})
	if result.Code != "authentication_required" || result.State != nil {
		t.Fatal("corrupt state must not be silently replaced")
	}
}

func TestErrorRedaction(t *testing.T) {
	req := request{Email: "test@example.invalid", Password: "secret-password", Code: "123456"}
	got := safeError(errors.New(req.Email+" "+req.Password+" "+req.Code), &req)
	for _, secret := range []string{req.Email, req.Password, req.Code} {
		if strings.Contains(got, secret) {
			t.Fatal("credential leaked into error")
		}
	}
}
