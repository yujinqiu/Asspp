// Asspp's private, single-request stdio bridge to the pinned ipatool library.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/majd/ipatool/v2/pkg/util/machine"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
	"github.com/schollz/progressbar/v3"
)

type request struct {
	Operation string            `json:"operation"`
	Session   session           `json:"-"`
	State     []byte            `json:"state,omitempty"`
	Email     string            `json:"email"`
	Password  string            `json:"password"`
	Code      string            `json:"code"`
	AppID     int64             `json:"appID"`
	BundleID  string            `json:"bundleID"`
	Platform  appstore.Platform `json:"platform"`
	VersionID string            `json:"versionID"`
	Output    string            `json:"output"`
}
type accountSummary struct {
	Email string `json:"email"`
	Name  string `json:"name"`
	Store string `json:"store"`
	DSID  string `json:"dsid"`
}
type response struct {
	Kind        string          `json:"kind"`
	State       []byte          `json:"state,omitempty"`
	Account     *accountSummary `json:"account,omitempty"`
	Error       string          `json:"error,omitempty"`
	Code        string          `json:"code,omitempty"`
	Versions    []string        `json:"versions,omitempty"`
	Version     string          `json:"version,omitempty"`
	ReleaseDate string          `json:"releaseDate,omitempty"`
	Fraction    float64         `json:"fraction,omitempty"`
}

func main() {
	// Never send diagnostics to stdout: it carries private session material.
	var req request
	if err := json.NewDecoder(io.LimitReader(os.Stdin, 8<<20)).Decode(&req); err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(response{Kind: "result", Code: "invalid_request", Error: "Invalid store request"})
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 30*time.Minute)
	defer cancel()
	result := execute(ctx, &req, func(value response) { _ = json.NewEncoder(os.Stdout).Encode(value) })
	result.Kind = "result"
	_ = json.NewEncoder(os.Stdout).Encode(result)
}

func execute(ctx context.Context, req *request, emit func(response)) response {
	if len(req.State) > 0 {
		if err := json.Unmarshal(req.State, &req.Session); err != nil {
			return response{Error: "Invalid saved authentication state; sign in again", Code: "authentication_required"}
		}
	}
	if req.Session.Keys == nil {
		req.Session.Keys = make(map[string][]byte)
	}
	if req.Operation == "import" {
		if err := importAccount(req); err != nil {
			return response{Error: safeError(err, req), Code: "authentication_required"}
		}
		req.Operation = "account"
	}
	jar, err := newSessionJar(req.Session.Cookies)
	if err != nil {
		return response{Error: "Unable to restore authentication cookies"}
	}
	os := operatingsystem.New()
	store := appstore.NewAppStore(appstore.Args{Keychain: &req.Session, CookieJar: jar, OperatingSystem: os, Machine: machine.New(machine.Args{OS: os})})
	result, err := perform(ctx, store, req, emit)
	req.Session.Cookies = jar.snapshot()
	info, accountErr := store.AccountInfo()
	if accountErr == nil {
		acc := info.Account
		acc.Password = ""
		data, _ := json.Marshal(acc)
		_ = req.Session.Set("account", data)
		result.Account = &accountSummary{Email: acc.Email, Name: acc.Name, Store: strings.Split(acc.StoreFront, "-")[0], DSID: acc.DirectoryServicesID}
	}
	result.State, _ = json.Marshal(req.Session)
	if err != nil {
		result.Code = errorCode(err)
		result.Error = safeError(err, req)
	}
	return result
}

func perform(ctx context.Context, store appstore.AppStore, req *request, emit func(response)) (response, error) {
	if req.Operation == "login" {
		_, err := store.Login(appstore.LoginInput{Email: req.Email, Password: req.Password, AuthCode: req.Code})
		return response{}, err
	}
	info, err := store.AccountInfo()
	if err != nil {
		return response{}, err
	}
	if req.Operation == "account" {
		return response{}, nil
	}
	if req.Platform == "" {
		req.Platform = appstore.PlatformIPhone
	}
	lookup, err := store.Lookup(appstore.LookupInput{Account: info.Account, AppID: req.AppID, BundleID: req.BundleID, Platform: req.Platform})
	if err != nil {
		return response{}, err
	}
	switch req.Operation {
	case "purchase":
		return response{}, store.Purchase(appstore.PurchaseInput{Account: info.Account, App: lookup.App, Platform: req.Platform})
	case "download":
		if req.Output == "" {
			return response{}, errors.New("download destination is missing")
		}
		bar := progressbar.NewOptions64(-1, progressbar.OptionSetWriter(io.Discard))
		done := make(chan struct{})
		var worker sync.WaitGroup
		worker.Add(1)
		go func() {
			defer worker.Done()
			ticker := time.NewTicker(300 * time.Millisecond)
			defer ticker.Stop()
			for {
				select {
				case <-done:
					return
				case <-ticker.C:
					state := bar.State()
					if state.Max > 0 {
						emit(response{Kind: "progress", Fraction: max(0, min(0.99, state.CurrentPercent))})
					}
				}
			}
		}()
		_, err := store.Download(appstore.DownloadInput{Context: ctx, Account: info.Account, App: lookup.App, OutputPath: req.Output, ExternalVersionID: req.VersionID, Platform: req.Platform, Progress: bar})
		close(done)
		worker.Wait()
		return response{}, err
	case "versions":
		out, err := store.ListVersions(appstore.ListVersionsInput{Context: ctx, Account: info.Account, App: lookup.App, Platform: req.Platform})
		return response{Versions: out.ExternalVersionIdentifiers}, err
	case "metadata":
		out, err := store.GetVersionMetadata(appstore.GetVersionMetadataInput{Context: ctx, Account: info.Account, App: lookup.App, Platform: req.Platform, VersionID: req.VersionID})
		return response{Version: out.DisplayVersion, ReleaseDate: out.ReleaseDate.Format(time.RFC3339)}, err
	default:
		return response{}, fmt.Errorf("unsupported store operation")
	}
}

func errorCode(err error) string {
	switch {
	case errors.Is(err, appstore.ErrAuthCodeRequired):
		return "verification_required"
	case errors.Is(err, appstore.ErrLicenseRequired):
		return "license_required"
	case errors.Is(err, appstore.ErrPasswordTokenExpired):
		return "authentication_required"
	default:
		return "store_error"
	}
}

func safeError(err error, req *request) string {
	message := err.Error()
	for _, secret := range []string{req.Password, req.Code, req.Email} {
		if secret != "" {
			message = strings.ReplaceAll(message, secret, "<redacted>")
		}
	}
	if len(message) > 1500 {
		message = message[:1500]
	}
	return message
}
