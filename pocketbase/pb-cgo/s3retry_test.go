package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// Сервер-заглушка хранилища: отвечает по сценарию на каждую попытку и
// запоминает, какие тела пришли.
type fakeStore struct {
	mu     sync.Mutex
	bodies []string
	reply  func(attempt int, w http.ResponseWriter, r *http.Request)
}

func (s *fakeStore) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	s.mu.Lock()
	s.bodies = append(s.bodies, string(body))
	attempt := len(s.bodies)
	s.mu.Unlock()
	s.reply(attempt, w, r)
}

func (s *fakeStore) attempts() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.bodies)
}

func testRetry() *s3Retry {
	retry := newS3Retry(http.DefaultTransport)
	retry.headerWait = 300 * time.Millisecond
	retry.perMegabyte = 0
	retry.backoff = []time.Duration{time.Millisecond, time.Millisecond}
	retry.logf = func(string, ...any) {}
	return retry
}

func s3Request(t *testing.T, ctx context.Context, method, url, body string) *http.Request {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = bytes.NewReader([]byte(body))
	}
	req, err := http.NewRequestWithContext(ctx, method, url, reader)
	if err != nil {
		t.Fatal(err)
	}
	// так подписывает запросы клиент S3 в PocketBase
	req.Header.Set("Authorization", "AWS4-HMAC-SHA256 Credential=test/20261025/hel1/s3/aws4_request")
	return req
}

func TestS3RetryRepeatsGatewayTimeout(t *testing.T) {
	store := &fakeStore{reply: func(attempt int, w http.ResponseWriter, _ *http.Request) {
		if attempt == 1 {
			w.WriteHeader(http.StatusGatewayTimeout)
			return
		}
		w.WriteHeader(http.StatusOK)
	}}
	server := httptest.NewServer(store)
	defer server.Close()

	resp, err := testRetry().RoundTrip(s3Request(t, context.Background(), http.MethodPut, server.URL+"/photo.webp", "кадр"))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("ответ %d, ждали 200 со второй попытки", resp.StatusCode)
	}
	if got := store.bodies; len(got) != 2 || got[0] != "кадр" || got[1] != "кадр" {
		t.Fatalf("тела попыток %q, ждали дважды тот же файл", got)
	}
}

func TestS3RetryCutsHungAttempt(t *testing.T) {
	release := make(chan struct{})
	store := &fakeStore{reply: func(attempt int, w http.ResponseWriter, _ *http.Request) {
		if attempt == 1 {
			<-release // хранилище молчит
			return
		}
		w.WriteHeader(http.StatusOK)
	}}
	server := httptest.NewServer(store)
	defer server.Close()
	defer close(release) // сперва отпускаем молчащую попытку, потом гасим сервер

	// без повтора запрос висел бы, пока не отменят: тесту хватит пяти секунд
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	started := time.Now()
	resp, err := testRetry().RoundTrip(s3Request(t, ctx, http.MethodPut, server.URL+"/photo.webp", "кадр"))
	if err != nil {
		t.Fatalf("зависшую попытку не оборвали и не повторили: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || store.attempts() != 2 {
		t.Fatalf("ответ %d за %d попыток, ждали 200 со второй", resp.StatusCode, store.attempts())
	}
	if spent := time.Since(started); spent > 2*time.Second {
		t.Fatalf("зависшая попытка держала %s, срок попытки 300 мс", spent)
	}
}

func TestS3RetryGivesUpAndReturnsStoreAnswer(t *testing.T) {
	store := &fakeStore{reply: func(_ int, w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusGatewayTimeout)
		io.WriteString(w, "<Error><Code>GatewayTimeout</Code></Error>")
	}}
	server := httptest.NewServer(store)
	defer server.Close()

	resp, err := testRetry().RoundTrip(s3Request(t, context.Background(), http.MethodPut, server.URL+"/photo.webp", "кадр"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusGatewayTimeout || !strings.Contains(string(body), "GatewayTimeout") {
		t.Fatalf("ответ %d %q: PocketBase должен увидеть последний ответ хранилища", resp.StatusCode, body)
	}
	if store.attempts() != 3 {
		t.Fatalf("%d попыток, ждали 3", store.attempts())
	}
}

func TestS3RetryLeavesOtherRequestsAlone(t *testing.T) {
	store := &fakeStore{reply: func(_ int, w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusGatewayTimeout)
	}}
	server := httptest.NewServer(store)
	defer server.Close()

	req, _ := http.NewRequest(http.MethodGet, server.URL+"/oauth", nil)
	resp, err := testRetry().RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if store.attempts() != 1 {
		t.Fatalf("запрос не к хранилищу повторён %d раз", store.attempts())
	}
}

func TestS3RetryDoesNotRepeatPost(t *testing.T) {
	store := &fakeStore{reply: func(_ int, w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusGatewayTimeout)
	}}
	server := httptest.NewServer(store)
	defer server.Close()

	resp, err := testRetry().RoundTrip(s3Request(t, context.Background(), http.MethodPost, server.URL+"/video.mp4?uploads", ""))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if store.attempts() != 1 {
		t.Fatalf("начало составной загрузки повторено %d раз: новая загрузка осталась бы мусором", store.attempts())
	}
}

func TestS3RetryKeepsSlowBodyAfterHeaders(t *testing.T) {
	store := &fakeStore{reply: func(_ int, w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		for i := 0; i < 6; i++ {
			io.WriteString(w, "кусок")
			w.(http.Flusher).Flush()
			time.Sleep(150 * time.Millisecond) // всего 900 мс, срок попытки 300 мс
		}
	}}
	server := httptest.NewServer(store)
	defer server.Close()

	resp, err := testRetry().RoundTrip(s3Request(t, context.Background(), http.MethodGet, server.URL+"/video.mp4", ""))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil || string(body) != strings.Repeat("кусок", 6) {
		t.Fatalf("файл оборван: %q, %v", body, err)
	}
	if store.attempts() != 1 {
		t.Fatalf("%d попыток, медленная отдача не повод повторять", store.attempts())
	}
}

func TestS3RetryStopsWhenCallerCancels(t *testing.T) {
	release := make(chan struct{})
	store := &fakeStore{reply: func(_ int, _ http.ResponseWriter, _ *http.Request) {
		<-release
	}}
	server := httptest.NewServer(store)
	defer server.Close()
	defer close(release)

	retry := testRetry()
	retry.headerWait = 10 * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	started := time.Now()
	_, err := retry.RoundTrip(s3Request(t, ctx, http.MethodPut, server.URL+"/photo.webp", "кадр"))
	if err == nil {
		t.Fatal("ждали ошибку отмены")
	}
	if store.attempts() != 1 || time.Since(started) > 2*time.Second {
		t.Fatalf("%d попыток за %s: отменённый запрос повторять некому", store.attempts(), time.Since(started))
	}
}

func TestS3RetryWaitGrowsWithBody(t *testing.T) {
	retry := newS3Retry(http.DefaultTransport)
	read := s3Request(t, context.Background(), http.MethodGet, "http://store/a", "")
	part := s3Request(t, context.Background(), http.MethodPut, "http://store/b", strings.Repeat("x", 6<<20))
	if got := retry.waitFor(read); got != retry.headerWait {
		t.Fatalf("срок для запроса без тела %s", got)
	}
	if got, want := retry.waitFor(part), retry.headerWait+6*retry.perMegabyte; got != want {
		t.Fatalf("срок для части в 6 МБ %s, ждали %s", got, want)
	}
}
