package main

import (
	"context"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// Посредник между клиентом и хранилищем: по команде перестаёт пропускать байты
// по уже открытым соединениям, а новые пропускает. Так выглядел сбой 26.10.2026:
// PocketBase держал к Hetzner одно соединение HTTP/2, оно подвисало, и вставали
// все загрузки и чтения разом, а свежие соединения в те же секунды работали.
type freezingProxy struct {
	listener net.Listener
	target   string
	mu       sync.Mutex
	frozen   []*frozenGate
}

type frozenGate struct {
	mu     sync.Mutex
	closed bool
}

func (g *frozenGate) pass() bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	return !g.closed
}

func newFreezingProxy(t *testing.T, target string) *freezingProxy {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	proxy := &freezingProxy{listener: listener, target: target}
	go proxy.serve()
	t.Cleanup(func() { listener.Close() })
	return proxy
}

func (p *freezingProxy) serve() {
	for {
		client, err := p.listener.Accept()
		if err != nil {
			return
		}
		server, err := net.Dial("tcp", p.target)
		if err != nil {
			client.Close()
			continue
		}
		gate := &frozenGate{}
		p.mu.Lock()
		p.frozen = append(p.frozen, gate)
		p.mu.Unlock()
		go pipeThrough(gate, client, server)
		go pipeThrough(gate, server, client)
	}
}

// Байты идут дальше, пока ворота открыты; после заморозки читаются и молча
// выбрасываются, соединение при этом не рвётся.
func pipeThrough(gate *frozenGate, from, to net.Conn) {
	buffer := make([]byte, 32<<10)
	for {
		n, err := from.Read(buffer)
		if n > 0 && gate.pass() {
			to.Write(buffer[:n])
		}
		if err != nil {
			to.Close()
			return
		}
	}
}

// Замораживает все соединения, открытые до этой минуты.
func (p *freezingProxy) freezeOpen() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, gate := range p.frozen {
		gate.mu.Lock()
		gate.closed = true
		gate.mu.Unlock()
	}
}

func (p *freezingProxy) url() string { return "https://" + p.listener.Addr().String() }

func storeWithHTTP2(t *testing.T) (*httptest.Server, *tls.Config) {
	t.Helper()
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.Write([]byte("ok"))
	}))
	server.EnableHTTP2 = true
	server.StartTLS()
	t.Cleanup(server.Close)
	trust := server.Client().Transport.(*http.Transport).TLSClientConfig.Clone()
	return server, trust
}

func quickRetry(store http.RoundTripper) *s3Retry {
	retry := newS3Retry(http.DefaultTransport)
	retry.store = store
	retry.headerWait = 400 * time.Millisecond
	retry.perMegabyte = 0
	retry.backoff = []time.Duration{time.Millisecond, time.Millisecond}
	retry.logf = func(string, ...any) {}
	return retry
}

func TestS3StoreTransportSurvivesFrozenConnection(t *testing.T) {
	server, trust := storeWithHTTP2(t)
	proxy := newFreezingProxy(t, server.Listener.Addr().String())
	retry := quickRetry(newS3StoreTransport(trust))
	client := &http.Client{Transport: retry}

	first, err := client.Do(s3Request(t, context.Background(), http.MethodPut, proxy.url()+"/togetherly/a.png", "кадр"))
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, first.Body)
	first.Body.Close()
	if first.Proto != "HTTP/1.1" {
		t.Fatalf("к хранилищу нужен HTTP/1.1, а пошёл %s: одно общее соединение HTTP/2 топит все запросы разом", first.Proto)
	}

	proxy.freezeOpen()
	second, err := client.Do(s3Request(t, context.Background(), http.MethodPut, proxy.url()+"/togetherly/b.png", "кадр"))
	if err != nil {
		t.Fatalf("после зависшего соединения повтор обязан пройти по новому: %v", err)
	}
	second.Body.Close()
	if second.StatusCode != http.StatusOK {
		t.Fatalf("ответ %d", second.StatusCode)
	}
}

// Так было до правки: транспорт по умолчанию держит одно соединение HTTP/2, и
// все три попытки уходят в него же. Тест держит причину на виду.
func TestS3OverSharedHTTP2ConnectionAllAttemptsHang(t *testing.T) {
	server, trust := storeWithHTTP2(t)
	proxy := newFreezingProxy(t, server.Listener.Addr().String())
	shared := http.DefaultTransport.(*http.Transport).Clone()
	shared.TLSClientConfig = trust
	shared.ForceAttemptHTTP2 = true
	retry := quickRetry(shared)
	client := &http.Client{Transport: retry}

	first, err := client.Do(s3Request(t, context.Background(), http.MethodPut, proxy.url()+"/togetherly/a.png", "кадр"))
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, first.Body)
	first.Body.Close()
	if first.Proto != "HTTP/2.0" {
		t.Skipf("хранилище в тесте ответило по %s, сравнивать не с чем", first.Proto)
	}

	proxy.freezeOpen()
	if _, err := client.Do(s3Request(t, context.Background(), http.MethodPut, proxy.url()+"/togetherly/b.png", "кадр")); err == nil {
		t.Fatal("ждали, что по общему соединению HTTP/2 все попытки зависнут")
	}
}

// Другие запросы PocketBase (вход через Google, Apple и прочее) идут как раньше,
// через общий транспорт, а не через транспорт хранилища.
func TestS3StoreTransportOnlyForStore(t *testing.T) {
	var sawStore, sawOther bool
	retry := newS3Retry(roundTripFunc(func(*http.Request) (*http.Response, error) {
		sawOther = true
		return &http.Response{StatusCode: 200, Body: http.NoBody}, nil
	}))
	retry.store = roundTripFunc(func(*http.Request) (*http.Response, error) {
		sawStore = true
		return &http.Response{StatusCode: 200, Body: http.NoBody}, nil
	})
	plain, _ := http.NewRequest(http.MethodGet, "https://accounts.google.com/x", nil)
	retry.RoundTrip(plain)
	if !sawOther || sawStore {
		t.Fatal("обычный запрос обязан идти через общий транспорт")
	}
	sawOther = false
	post := s3Request(t, context.Background(), http.MethodPost, "https://hel1.example/togetherly/x?uploads", "")
	retry.RoundTrip(post)
	if !sawStore || sawOther {
		t.Fatal("любой запрос к хранилищу, и POST тоже, обязан идти через транспорт хранилища")
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
