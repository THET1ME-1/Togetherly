package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

// Вторая попытка идёт другим путём (TOG-41, 07.11.2026). С 02.11.2026 запросы
// к Хельсинки идут туннелем IPv6, и срывы стали окнами на этом пути: за сутки
// на 07.11 21 запись не прошла всеми тремя попытками, и все три шли одним и
// тем же путём. Прямой путь по IPv4 в те же минуты отвечал.
func TestS3RetrySecondAttemptTakesSparePath(t *testing.T) {
	var mu sync.Mutex
	var order []string
	note := func(path string) {
		mu.Lock()
		order = append(order, path)
		mu.Unlock()
	}
	retry := testRetry()
	retry.store = roundTripFunc(func(*http.Request) (*http.Response, error) {
		note("туннель")
		return &http.Response{StatusCode: http.StatusGatewayTimeout, Body: http.NoBody}, nil
	})
	retry.spare = roundTripFunc(func(*http.Request) (*http.Response, error) {
		note("IPv4")
		return &http.Response{StatusCode: http.StatusOK, Body: http.NoBody}, nil
	})
	var logs []string
	retry.logf = func(format string, args ...any) { logs = append(logs, fmt.Sprintf(format, args...)) }

	resp, err := retry.RoundTrip(s3Request(t, context.Background(), http.MethodPut, "https://hel1.example/togetherly/a.webp", "кадр"))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("ответ %d", resp.StatusCode)
	}
	if strings.Join(order, ",") != "туннель,IPv4" {
		t.Fatalf("пути попыток: %v, ждали туннель, потом IPv4", order)
	}
	if !strings.Contains(strings.Join(logs, "\n"), "IPv4") {
		t.Fatalf("в журнале не видно, каким путём прошло: %v", logs)
	}
}

func TestS3RetryThirdAttemptReturnsToMainPath(t *testing.T) {
	var order []string
	retry := testRetry()
	retry.store = roundTripFunc(func(*http.Request) (*http.Response, error) {
		order = append(order, "туннель")
		if len(order) == 1 {
			return nil, fmt.Errorf("обрыв")
		}
		return &http.Response{StatusCode: http.StatusOK, Body: http.NoBody}, nil
	})
	retry.spare = roundTripFunc(func(*http.Request) (*http.Response, error) {
		order = append(order, "IPv4")
		return &http.Response{StatusCode: http.StatusBadGateway, Body: http.NoBody}, nil
	})
	resp, err := retry.RoundTrip(s3Request(t, context.Background(), http.MethodGet, "https://hel1.example/togetherly/a.webp", ""))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if strings.Join(order, ",") != "туннель,IPv4,туннель" {
		t.Fatalf("пути попыток: %v", order)
	}
}

// Запасного пути нет (тесты соединений, прежняя сборка) — все попытки идут
// основным, как раньше.
func TestS3RetryWithoutSparePath(t *testing.T) {
	calls := 0
	retry := testRetry()
	retry.spare = nil
	retry.store = roundTripFunc(func(*http.Request) (*http.Response, error) {
		calls++
		if calls < 3 {
			return &http.Response{StatusCode: http.StatusServiceUnavailable, Body: http.NoBody}, nil
		}
		return &http.Response{StatusCode: http.StatusOK, Body: http.NoBody}, nil
	})
	resp, err := retry.RoundTrip(s3Request(t, context.Background(), http.MethodGet, "https://hel1.example/togetherly/a.webp", ""))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if calls != 3 {
		t.Fatalf("попыток основным путём %d, ждали 3", calls)
	}
}

// Запасной транспорт открывает соединения только по IPv4.
func TestS3SpareTransportDialsIPv4(t *testing.T) {
	transport := newS3StoreTransportOver(nil, "tcp4")
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if _, err := transport.DialContext(ctx, "tcp", "[::1]:1"); err == nil || !strings.Contains(err.Error(), "address") {
		t.Fatalf("адрес IPv6 обязан отвергаться, а не соединяться: %v", err)
	}
}
