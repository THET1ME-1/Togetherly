package main

// Повтор запросов PocketBase к хранилищу файлов (TOG-41, 25.10.2026).
//
// Хранилище Hetzner (Хельсинки) изредка не отвечает: PocketBase ждал ответа
// 120 секунд и получал 504 GatewayTimeout, человеку уходило 400 «Failed to
// create record.», и фото не сохранялось. После переезда бакета 24.10.2026
// так срывалось 2–9 загрузок в час. Повтор того же запроса проходит: rclone,
// копируя бакет, видел те же 504 и брал их со второй попытки. У клиента S3 в
// PocketBase своего повтора нет, он шлёт запрос через http.DefaultClient один
// раз, поэтому сборка оборачивает транспорт этого клиента (main).
//
// Повторяются только запросы к хранилищу (подпись AWS4-HMAC-SHA256) и только
// GET, HEAD, PUT и DELETE: они идемпотентны. PocketBase шлёт файл и части
// составной загрузки из памяти (bytes.Reader), у таких запросов есть GetBody,
// и повтор отправляет то же тело под тот же ключ. POST (начало и конец
// составной загрузки) не повторяется: повтор начала оставил бы в бакете
// брошенную загрузку. Подпись запроса живёт 15 минут, хранилище принимает её
// и при повторе.
//
// Повод для повтора: сетевая ошибка, ответ 500, 502, 503, 504 или зависание —
// заголовков ответа нет дольше срока попытки. Срок считается до заголовков, а
// не до конца тела: видео, которое PocketBase отдаёт человеку минутами,
// повтор не оборвёт. Для записи в срок входит и отправка тела, поэтому к
// базовому сроку прибавляется время на каждый мегабайт.

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

type s3Retry struct {
	base http.RoundTripper
	// сколько всего попыток, включая первую
	attempts int
	// срок до заголовков ответа для запроса без тела
	headerWait time.Duration
	// прибавка к сроку за каждый мегабайт тела: запись ~13 МБ/с, с запасом
	perMegabyte time.Duration
	// пауза перед второй, третьей… попыткой
	backoff []time.Duration
	logf    func(format string, args ...any)
}

// Сроки сведены с приложением: маленький файл оно ждёт 60 секунд
// (kUploadTimeoutMin в lib/models/upload_timeout.dart), и три зависшие
// попытки с паузами (15 + 0,5 + 15 + 1 + 15 = 46,5 с) укладываются раньше.
// Иначе приложение сдалось бы первым и прислало файл ещё раз, а запись от
// поздней удачной попытки осталась бы лишней. Обычная запись в Hetzner идёт
// доли секунды.
func newS3Retry(base http.RoundTripper) *s3Retry {
	return &s3Retry{
		base:        base,
		attempts:    3,
		headerWait:  15 * time.Second,
		perMegabyte: 2 * time.Second,
		backoff:     []time.Duration{500 * time.Millisecond, time.Second},
		logf:        log.Printf,
	}
}

var errS3Hung = errors.New("хранилище не ответило за срок попытки")

// Запрос клиента S3 из PocketBase: только его и повторяем.
func isS3Request(req *http.Request) bool {
	return strings.HasPrefix(req.Header.Get("Authorization"), "AWS4-HMAC-SHA256")
}

func idempotentMethod(method string) bool {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPut, http.MethodDelete:
		return true
	}
	return false
}

func retryableStatus(code int) bool {
	return code == http.StatusInternalServerError || code == http.StatusBadGateway ||
		code == http.StatusServiceUnavailable || code == http.StatusGatewayTimeout
}

// Повторять можно, только если тело запроса можно отправить заново.
func (t *s3Retry) canRetry(req *http.Request) bool {
	if !isS3Request(req) || !idempotentMethod(req.Method) {
		return false
	}
	return req.Body == nil || req.Body == http.NoBody || req.GetBody != nil
}

// Срок попытки до заголовков ответа: база плюс время на отправку тела.
func (t *s3Retry) waitFor(req *http.Request) time.Duration {
	size := req.ContentLength
	if size < 0 {
		size = 0
	}
	return t.headerWait + time.Duration(size*int64(t.perMegabyte)/(1<<20))
}

func (t *s3Retry) RoundTrip(req *http.Request) (*http.Response, error) {
	if !t.canRetry(req) {
		return t.base.RoundTrip(req)
	}
	for attempt := 1; ; attempt++ {
		resp, err := t.try(req, attempt)
		if err == nil && !retryableStatus(resp.StatusCode) {
			if attempt > 1 {
				t.logf("[s3-retry] %s %s: прошло с попытки %d", req.Method, req.URL.Path, attempt)
			}
			return resp, nil
		}
		// запрос отменил тот, кто его послал: повторять некому
		if req.Context().Err() != nil {
			return resp, err
		}
		if attempt >= t.attempts {
			// последний ответ хранилища отдаём PocketBase как есть: он сам
			// разберёт ошибку и запишет её в журнал
			t.logf("[s3-retry] %s %s: %d попытки не прошли, последняя: %s",
				req.Method, req.URL.Path, attempt, describeS3Failure(resp, err))
			return resp, err
		}
		t.logf("[s3-retry] %s %s: попытка %d: %s, повторяю",
			req.Method, req.URL.Path, attempt, describeS3Failure(resp, err))
		if resp != nil {
			io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
			resp.Body.Close()
		}
		if !t.pause(req.Context(), attempt) {
			return nil, req.Context().Err()
		}
	}
}

// Одна попытка со своим сроком до заголовков ответа.
func (t *s3Retry) try(req *http.Request, attempt int) (*http.Response, error) {
	ctx, cancel := context.WithCancel(req.Context())
	attemptReq := req.Clone(ctx)
	if attempt > 1 && req.GetBody != nil {
		body, err := req.GetBody()
		if err != nil {
			cancel()
			return nil, err
		}
		attemptReq.Body = body
	}
	wait := t.waitFor(req)
	timer := time.AfterFunc(wait, cancel)
	resp, err := t.base.RoundTrip(attemptReq)
	if !timer.Stop() {
		// срок вышел раньше заголовков: это зависание, а не ответ
		if err == nil {
			resp.Body.Close()
		}
		cancel()
		return nil, fmt.Errorf("%w (%s)", errS3Hung, wait)
	}
	if err != nil {
		cancel()
		return nil, err
	}
	// тело PocketBase читает уже без срока, а контекст попытки закрывается
	// вместе с телом
	resp.Body = &bodyWithCancel{ReadCloser: resp.Body, cancel: cancel}
	return resp, nil
}

func (t *s3Retry) pause(ctx context.Context, attempt int) bool {
	if len(t.backoff) == 0 {
		return ctx.Err() == nil
	}
	index := attempt - 1
	if index >= len(t.backoff) {
		index = len(t.backoff) - 1
	}
	timer := time.NewTimer(t.backoff[index])
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func describeS3Failure(resp *http.Response, err error) string {
	if err != nil {
		return err.Error()
	}
	return fmt.Sprintf("ответ %d", resp.StatusCode)
}

type bodyWithCancel struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (b *bodyWithCancel) Close() error {
	err := b.ReadCloser.Close()
	b.cancel()
	return err
}
