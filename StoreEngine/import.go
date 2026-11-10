package main

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/byteness/keyring"
	cookiejar "github.com/juju/persistent-cookiejar"
)

// Import is explicit and read-only: the original ipatool account stays intact.
func importAccount(req *request) error {
	ring, err := keyring.Open(keyring.Config{AllowedBackends: []keyring.BackendType{keyring.KeychainBackend}, ServiceName: "ipatool-auth.service"})
	if err != nil {
		return err
	}
	for _, key := range []string{"account", "anisette-v4"} {
		item, err := ring.Get(key)
		if err != nil {
			return err
		}
		req.Session.Keys[key] = item.Data
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	base := filepath.Join(home, ".ipatool")
	if _, err := os.Stat(base); os.IsNotExist(err) {
		for _, name := range []string{"XDG_STATE_HOME", "XDG_DATA_HOME"} {
			if path := os.Getenv(name); filepath.IsAbs(path) {
				base = filepath.Join(path, "ipatool")
				break
			}
		}
	}
	jar, err := cookiejar.New(&cookiejar.Options{Filename: filepath.Join(base, "cookies")})
	if err != nil {
		return err
	}
	for _, cookie := range jar.AllCookies() {
		host := strings.TrimPrefix(cookie.Domain, ".")
		u := url.URL{Scheme: "https", Host: host, Path: cookie.Path}
		req.Session.Cookies = append(req.Session.Cookies, cookieRecord{URL: u.String(), Cookie: cookie})
	}
	// AccountInfo reads from the in-memory imported Keychain on the same request.
	var value map[string]any
	if err = json.Unmarshal(req.Session.Keys["account"], &value); err != nil {
		return err
	}
	delete(value, "password")
	req.Session.Keys["account"], err = json.Marshal(value)
	return err
}
