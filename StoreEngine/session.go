package main

import (
	"errors"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/publicsuffix"
)

// Session is opaque to Swift and stored only in the account's Keychain item.
type session struct {
	Keys    map[string][]byte `json:"keys"`
	Cookies []cookieRecord    `json:"cookies"`
}

type cookieRecord struct {
	URL    string       `json:"url"`
	Cookie *http.Cookie `json:"cookie"`
}

func (r cookieRecord) identity() string {
	domain := strings.ToLower(strings.TrimPrefix(r.Cookie.Domain, "."))
	if domain == "" {
		u, _ := url.Parse(r.URL)
		domain = strings.ToLower(u.Hostname())
	}
	return domain + "\x00" + r.Cookie.Path + "\x00" + r.Cookie.Name
}

func (s *session) Get(key string) ([]byte, error) {
	value, ok := s.Keys[key]
	if !ok {
		return nil, errors.New("authentication state is missing; sign in again")
	}
	return value, nil
}
func (s *session) Set(key string, value []byte) error { s.Keys[key] = value; return nil }
func (s *session) Remove(key string) error            { delete(s.Keys, key); return nil }

type sessionJar struct {
	*cookiejar.Jar
	mu      sync.Mutex
	records []cookieRecord
}

func newSessionJar(records []cookieRecord) (*sessionJar, error) {
	jar, err := cookiejar.New(&cookiejar.Options{PublicSuffixList: publicsuffix.List})
	if err != nil {
		return nil, err
	}
	j := &sessionJar{Jar: jar}
	for _, record := range records {
		u, err := url.Parse(record.URL)
		if err == nil && record.Cookie != nil {
			j.SetCookies(u, []*http.Cookie{record.Cookie})
		}
	}
	return j, nil
}

func (j *sessionJar) SetCookies(u *url.URL, cookies []*http.Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.Jar.SetCookies(u, cookies)
	for _, cookie := range cookies {
		copy := *cookie
		if !strings.HasPrefix(copy.Path, "/") {
			copy.Path = "/"
			if slash := strings.LastIndex(u.Path, "/"); slash > 0 {
				copy.Path = u.Path[:slash]
			}
		}
		if copy.MaxAge > 0 {
			copy.Expires = time.Now().Add(time.Duration(copy.MaxAge) * time.Second)
			copy.MaxAge = 0
		}
		record := cookieRecord{URL: u.Scheme + "://" + u.Host + u.Path, Cookie: &copy}
		filtered := j.records[:0]
		for _, old := range j.records {
			if old.identity() != record.identity() {
				filtered = append(filtered, old)
			}
		}
		j.records = filtered
		if copy.MaxAge >= 0 && (copy.Expires.IsZero() || copy.Expires.After(time.Now())) {
			j.records = append(j.records, record)
		}
	}
}

func (j *sessionJar) Save() error { return nil }
func (j *sessionJar) snapshot() []cookieRecord {
	j.mu.Lock()
	defer j.mu.Unlock()
	return append([]cookieRecord(nil), j.records...)
}
