package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// Склад свежих файлов на своём диске (10.11.2026).
//
// Хранилище временами держит запись файла по 20–70 секунд, и все обращения к
// нему в это время ждут. PocketBase бросал попытку через 15 секунд, начинал
// заново, и человеку уходило «не удалось загрузить»: 9–10.11.2026 так срывалось
// около 200 загрузок в сутки, а только что присланные картинки не открывались
// у партнёра. Со складом PocketBase получает «принято» сразу, чтение свежего
// файла идёт с диска, а в хранилище файл досылается в фоне.

// Поддельное хранилище: помнит, что в него записали, и умеет тянуть время.
type fakeBucket struct {
	mu      sync.Mutex
	objects map[string][]byte
	puts    int
	gets    int
	deletes []string
	auth    []string
	// сколько первых записей провалить и чем
	failPuts   int
	failStatus int
	// задержка перед ответом на запись
	putDelay time.Duration
}

func newFakeBucket() *fakeBucket {
	return &fakeBucket{objects: map[string][]byte{}, failStatus: http.StatusServiceUnavailable}
}

func (b *fakeBucket) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		body, _ := io.ReadAll(r.Body)
		b.mu.Lock()
		b.puts++
		b.auth = append(b.auth, r.Header.Get("Authorization")+" | "+r.Header.Get("X-Amz-Date"))
		fail := b.puts <= b.failPuts
		delay := b.putDelay
		b.mu.Unlock()
		time.Sleep(delay)
		if fail {
			w.WriteHeader(b.failStatus)
			return
		}
		b.mu.Lock()
		b.objects[r.URL.Path] = body
		b.mu.Unlock()
		w.Header().Set("ETag", `"из-хранилища"`)
	case http.MethodGet, http.MethodHead:
		b.mu.Lock()
		b.gets++
		body, ok := b.objects[r.URL.Path]
		b.mu.Unlock()
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "image/webp")
		w.Header().Set("Last-Modified", "Tue, 10 Nov 2026 12:00:00 GMT")
		w.Header().Set("ETag", `"из-хранилища"`)
		w.Header().Set("Content-Length", fmt.Sprint(len(body)))
		if r.Method == http.MethodGet {
			w.Write(body)
		}
	case http.MethodDelete:
		b.mu.Lock()
		delete(b.objects, r.URL.Path)
		b.deletes = append(b.deletes, r.URL.Path)
		b.mu.Unlock()
		w.WriteHeader(http.StatusNoContent)
	}
}

func (b *fakeBucket) stored(path string) ([]byte, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	body, ok := b.objects[path]
	return body, ok
}

func (b *fakeBucket) counts() (puts, gets int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.puts, b.gets
}

// Транспорт со складом поверх поддельного хранилища.
func spoolRetry(t *testing.T, bucket *fakeBucket, dir string) (*s3Retry, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(bucket)
	t.Cleanup(server.Close)
	retry := testRetry()
	retry.store = http.DefaultTransport
	retry.spare = http.DefaultTransport
	spool, err := newS3Spool(dir, retry)
	if err != nil {
		t.Fatal(err)
	}
	spool.secret.Store("секрет")
	spool.uploadWait = 2 * time.Second
	spool.retryPause = []time.Duration{5 * time.Millisecond}
	spool.logf = func(string, ...any) {}
	retry.spool = spool
	return retry, server
}

func signedRequest(t *testing.T, method, url, body string) *http.Request {
	t.Helper()
	req := s3Request(t, context.Background(), method, url, body)
	req.Header.Set("Authorization", "AWS4-HMAC-SHA256 Credential=ключ/20261110/hel1/s3/aws4_request, SignedHeaders=host;x-amz-date, Signature=старая")
	req.Header.Set("X-Amz-Date", "20261110T120000Z")
	req.Header.Set("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD")
	if body != "" {
		req.Header.Set("Content-Type", "image/webp")
		req.Header.Set("X-Amz-Meta-Original-Filename", "кадр.webp")
	}
	return req
}

func waitFor(t *testing.T, what string, done func() bool) {
	t.Helper()
	for i := 0; i < 400; i++ {
		if done() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("не дождались: %s", what)
}

func mustDo(t *testing.T, retry *s3Retry, req *http.Request) (*http.Response, []byte) {
	t.Helper()
	resp, err := retry.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	return resp, body
}

func TestSpoolAnswersPutAtOnceAndUploadsBehind(t *testing.T) {
	bucket := newFakeBucket()
	bucket.putDelay = 700 * time.Millisecond // хранилище тянет с записью
	retry, server := spoolRetry(t, bucket, t.TempDir())
	url := server.URL + "/togetherly/pbc_1/rec1/kadr.webp"

	started := time.Now()
	resp, _ := mustDo(t, retry, signedRequest(t, http.MethodPut, url, "содержимое кадра"))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("ответ на запись %d", resp.StatusCode)
	}
	if took := time.Since(started); took > 300*time.Millisecond {
		t.Fatalf("запись ждала хранилище %s, а должна ответить сразу", took)
	}
	if _, ok := bucket.stored("/togetherly/pbc_1/rec1/kadr.webp"); ok {
		t.Fatal("хранилище ещё не должно было принять файл")
	}

	// Партнёр просит файл сразу — он уже отдаётся, хранилище не спрашиваем.
	resp, body := mustDo(t, retry, signedRequest(t, http.MethodGet, url, ""))
	if resp.StatusCode != http.StatusOK || string(body) != "содержимое кадра" {
		t.Fatalf("чтение свежего файла: %d %q", resp.StatusCode, body)
	}
	if resp.Header.Get("Content-Type") != "image/webp" {
		t.Fatalf("тип файла потерялся: %q", resp.Header.Get("Content-Type"))
	}
	if resp.ContentLength != int64(len("содержимое кадра")) {
		t.Fatalf("длина %d", resp.ContentLength)
	}
	if _, gets := bucket.counts(); gets != 0 {
		t.Fatalf("чтение свежего файла сходило в хранилище %d раз", gets)
	}

	waitFor(t, "файл в хранилище", func() bool {
		_, ok := bucket.stored("/togetherly/pbc_1/rec1/kadr.webp")
		return ok
	})
	got, _ := bucket.stored("/togetherly/pbc_1/rec1/kadr.webp")
	if string(got) != "содержимое кадра" {
		t.Fatalf("в хранилище легло не то: %q", got)
	}
}

func TestSpoolKeepsTryingWhileStorageRefuses(t *testing.T) {
	bucket := newFakeBucket()
	bucket.failPuts = 4 // окно отказов: четыре раза подряд 503
	retry, server := spoolRetry(t, bucket, t.TempDir())
	url := server.URL + "/togetherly/pbc_1/rec2/kadr.webp"

	resp, _ := mustDo(t, retry, signedRequest(t, http.MethodPut, url, "кадр"))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("человек получил отказ %d, хотя файл принят на склад", resp.StatusCode)
	}
	waitFor(t, "файл в хранилище после окна отказов", func() bool {
		_, ok := bucket.stored("/togetherly/pbc_1/rec2/kadr.webp")
		return ok
	})
	if puts, _ := bucket.counts(); puts != 5 {
		t.Fatalf("попыток записи %d, ждали пять", puts)
	}
}

func TestSpoolSignsEveryUploadAfresh(t *testing.T) {
	// Подпись запроса живёт 15 минут, а хранилище может лежать дольше:
	// каждая досылка подписывается заново, своим временем.
	bucket := newFakeBucket()
	retry, server := spoolRetry(t, bucket, t.TempDir())
	mustDo(t, retry, signedRequest(t, http.MethodPut, server.URL+"/togetherly/pbc_1/rec3/kadr.webp", "кадр"))
	waitFor(t, "досылка", func() bool { puts, _ := bucket.counts(); return puts == 1 })
	bucket.mu.Lock()
	auth := bucket.auth[0]
	bucket.mu.Unlock()
	if strings.Contains(auth, "Signature=старая") || strings.Contains(auth, "20261110T120000Z") {
		t.Fatalf("досылка ушла с прежней подписью: %s", auth)
	}
	if !strings.Contains(auth, "Credential=ключ/") || !strings.Contains(auth, "/hel1/s3/aws4_request") {
		t.Fatalf("в подписи не тот ключ или область: %s", auth)
	}
}

func TestSpoolSignatureMatchesAmazonExample(t *testing.T) {
	// Пример из документации Amazon (Signature Version 4, GET Object).
	req, _ := http.NewRequest(http.MethodGet, "https://examplebucket.s3.amazonaws.com/test.txt", nil)
	req.Header.Set("Range", "bytes=0-9")
	req.Header.Set("X-Amz-Content-Sha256", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	signS3(req, "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "us-east-1",
		time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC))
	want := "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
	if !strings.Contains(req.Header.Get("Authorization"), want) {
		t.Fatalf("подпись не сошлась с примером Amazon: %s", req.Header.Get("Authorization"))
	}
}

func TestSpoolServesRangesAndHead(t *testing.T) {
	bucket := newFakeBucket()
	retry, server := spoolRetry(t, bucket, t.TempDir())
	url := server.URL + "/togetherly/pbc_1/rec4/golos.m4a"
	mustDo(t, retry, signedRequest(t, http.MethodPut, url, "0123456789"))

	head, _ := mustDo(t, retry, signedRequest(t, http.MethodHead, url, ""))
	if head.StatusCode != http.StatusOK || head.ContentLength != 10 || head.Header.Get("Content-Length") != "10" {
		t.Fatalf("проверка файла: %d длина %d", head.StatusCode, head.ContentLength)
	}
	if head.Header.Get("X-Amz-Meta-Original-Filename") != "кадр.webp" {
		t.Fatalf("метка файла потерялась: %v", head.Header)
	}

	for _, c := range []struct{ ask, want, span string }{
		{"bytes=2-5", "2345", "bytes 2-5/10"},
		{"bytes=7-", "789", "bytes 7-9/10"},
		{"bytes=-3", "789", "bytes 7-9/10"},
		{"bytes=4-100", "456789", "bytes 4-9/10"},
	} {
		req := signedRequest(t, http.MethodGet, url, "")
		req.Header.Set("Range", c.ask)
		resp, body := mustDo(t, retry, req)
		if resp.StatusCode != http.StatusPartialContent || string(body) != c.want || resp.Header.Get("Content-Range") != c.span {
			t.Fatalf("%s: ответ %d %q %q", c.ask, resp.StatusCode, body, resp.Header.Get("Content-Range"))
		}
	}
}

func TestSpoolResumesUploadAfterRestart(t *testing.T) {
	bucket := newFakeBucket()
	bucket.failPuts = 1000 // хранилище лежит
	dir := t.TempDir()
	retry, server := spoolRetry(t, bucket, dir)
	url := server.URL + "/togetherly/pbc_1/rec5/kadr.webp"
	mustDo(t, retry, signedRequest(t, http.MethodPut, url, "переживу перезапуск"))
	waitFor(t, "первая попытка", func() bool { puts, _ := bucket.counts(); return puts >= 1 })
	retry.spool.stop()

	// Сервер приложения перезапустили, хранилище ожило.
	bucket.mu.Lock()
	bucket.failPuts = 0
	bucket.mu.Unlock()
	again, _ := spoolRetry(t, bucket, dir)
	again.spool.resume()
	waitFor(t, "файл в хранилище после перезапуска", func() bool {
		body, ok := bucket.stored("/togetherly/pbc_1/rec5/kadr.webp")
		return ok && string(body) == "переживу перезапуск"
	})
	// И читается он по-прежнему со склада.
	_, body := mustDo(t, again, signedRequest(t, http.MethodGet, url, ""))
	if string(body) != "переживу перезапуск" {
		t.Fatalf("после перезапуска со склада пришло %q", body)
	}
}

func TestSpoolDeleteReachesStorageEvenBeforeUpload(t *testing.T) {
	bucket := newFakeBucket()
	bucket.putDelay = 300 * time.Millisecond
	retry, server := spoolRetry(t, bucket, t.TempDir())
	url := server.URL + "/togetherly/pbc_1/rec6/kadr.webp"
	mustDo(t, retry, signedRequest(t, http.MethodPut, url, "удалят раньше, чем долетит"))
	resp, _ := mustDo(t, retry, signedRequest(t, http.MethodDelete, url, ""))
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("ответ на удаление %d", resp.StatusCode)
	}
	resp, _ = mustDo(t, retry, signedRequest(t, http.MethodGet, url, ""))
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("удалённый файл всё ещё отдаётся: %d", resp.StatusCode)
	}
	// Досылка, которая была в полёте, не должна оставить файл в хранилище.
	time.Sleep(600 * time.Millisecond)
	waitFor(t, "файл убран из хранилища", func() bool {
		_, ok := bucket.stored("/togetherly/pbc_1/rec6/kadr.webp")
		return !ok
	})
}

func TestSpoolLeavesBigFilesAndPartsAlone(t *testing.T) {
	bucket := newFakeBucket()
	retry, server := spoolRetry(t, bucket, t.TempDir())
	retry.spool.maxPut = 8

	// Крупнее предела — пишется в хранилище напрямую, как раньше.
	mustDo(t, retry, signedRequest(t, http.MethodPut, server.URL+"/togetherly/pbc_1/rec7/video.mp4", "больше восьми байт"))
	if _, ok := bucket.stored("/togetherly/pbc_1/rec7/video.mp4"); !ok {
		t.Fatal("крупный файл не дошёл до хранилища напрямую")
	}
	// Часть составной загрузки — тоже напрямую.
	mustDo(t, retry, signedRequest(t, http.MethodPut, server.URL+"/togetherly/pbc_1/rec7/big.mp4?partNumber=1&uploadId=x", "часть"))
	if puts, _ := bucket.counts(); puts != 2 {
		t.Fatalf("записей в хранилище %d, ждали две прямых", puts)
	}
	if retry.spool.has("/togetherly/pbc_1/rec7/big.mp4") {
		t.Fatal("часть составной загрузки попала на склад")
	}
}

func TestSpoolRemembersWhatItRead(t *testing.T) {
	bucket := newFakeBucket()
	bucket.objects["/togetherly/pbc_1/old/avatar.webp"] = []byte("старая аватарка")
	retry, server := spoolRetry(t, bucket, t.TempDir())
	url := server.URL + "/togetherly/pbc_1/old/avatar.webp"

	for i := 0; i < 3; i++ {
		resp, body := mustDo(t, retry, signedRequest(t, http.MethodGet, url, ""))
		if resp.StatusCode != http.StatusOK || string(body) != "старая аватарка" {
			t.Fatalf("чтение %d: %d %q", i+1, resp.StatusCode, body)
		}
	}
	if _, gets := bucket.counts(); gets != 1 {
		t.Fatalf("в хранилище сходили %d раз, а хватило бы одного", gets)
	}
	// Прочитанное в хранилище заново не пишем.
	time.Sleep(50 * time.Millisecond)
	if puts, _ := bucket.counts(); puts != 0 {
		t.Fatalf("прочитанный файл зачем-то записан в хранилище: %d", puts)
	}
}

func TestSpoolPassesMissesThrough(t *testing.T) {
	bucket := newFakeBucket()
	retry, server := spoolRetry(t, bucket, t.TempDir())
	resp, _ := mustDo(t, retry, signedRequest(t, http.MethodGet, server.URL+"/togetherly/pbc_1/none/x.webp", ""))
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("несуществующий файл: %d", resp.StatusCode)
	}
	// Список бакета склад не трогает вовсе.
	resp, _ = mustDo(t, retry, signedRequest(t, http.MethodGet, server.URL+"/togetherly/?prefix=pbc_1", ""))
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("список бакета: %d", resp.StatusCode)
	}
}

func TestSpoolSweepDropsOldButNeverUnsent(t *testing.T) {
	bucket := newFakeBucket()
	retry, server := spoolRetry(t, bucket, t.TempDir())
	sent := server.URL + "/togetherly/pbc_1/rec8/sent.webp"
	mustDo(t, retry, signedRequest(t, http.MethodPut, sent, "долетел"))
	waitFor(t, "досылка", func() bool { _, ok := bucket.stored("/togetherly/pbc_1/rec8/sent.webp"); return ok })
	waitFor(t, "отметка о досылке", func() bool { return retry.spool.isStored("/togetherly/pbc_1/rec8/sent.webp") })

	bucket.mu.Lock()
	bucket.failPuts = 1000
	bucket.puts = 0
	bucket.mu.Unlock()
	mustDo(t, retry, signedRequest(t, http.MethodPut, server.URL+"/togetherly/pbc_1/rec8/waiting.webp", "ещё не долетел"))

	retry.spool.keep = 0 // всё долетевшее считается старым
	retry.spool.sweep()
	if retry.spool.has("/togetherly/pbc_1/rec8/sent.webp") {
		t.Fatal("долетевший старый файл остался на складе")
	}
	if !retry.spool.has("/togetherly/pbc_1/rec8/waiting.webp") {
		t.Fatal("со склада выброшен файл, которого ещё нет в хранилище")
	}
	// Долетевший читается дальше — уже из хранилища.
	_, body := mustDo(t, retry, signedRequest(t, http.MethodGet, sent, ""))
	if string(body) != "долетел" {
		t.Fatalf("после уборки файл не читается: %q", body)
	}
}

func TestSpoolOffMeansOldBehaviour(t *testing.T) {
	bucket := newFakeBucket()
	server := httptest.NewServer(bucket)
	defer server.Close()
	retry := testRetry()
	retry.store = http.DefaultTransport
	retry.spare = http.DefaultTransport
	mustDo(t, retry, signedRequest(t, http.MethodPut, server.URL+"/togetherly/pbc_1/rec9/kadr.webp", "напрямую"))
	if body, ok := bucket.stored("/togetherly/pbc_1/rec9/kadr.webp"); !ok || !bytes.Equal(body, []byte("напрямую")) {
		t.Fatal("без склада запись обязана идти в хранилище сразу")
	}
}

func TestPatientReadOutwaitsSlowStorage(t *testing.T) {
	// Хранилище держит ответ дольше срока первых попыток. Раньше все три
	// попытки обрывались по одному сроку, теперь последняя ждёт долго.
	var mu sync.Mutex
	calls := 0
	slow := roundTripFunc(func(req *http.Request) (*http.Response, error) {
		mu.Lock()
		calls++
		n := calls
		mu.Unlock()
		wait := 400 * time.Millisecond
		if n < 3 {
			wait = 5 * time.Second
		}
		select {
		case <-req.Context().Done():
			return nil, req.Context().Err()
		case <-time.After(wait):
			return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader("дождались")), Header: http.Header{}}, nil
		}
	})
	retry := testRetry()
	retry.store, retry.spare = slow, slow
	retry.headerWait = 50 * time.Millisecond
	retry.readWaits = []time.Duration{50 * time.Millisecond, 50 * time.Millisecond, 3 * time.Second}
	resp, body := mustDo(t, retry, signedRequest(t, http.MethodGet, "https://hel1.example/togetherly/pbc_1/slow/x.webp", ""))
	if resp.StatusCode != http.StatusOK || string(body) != "дождались" {
		t.Fatalf("терпеливое чтение: %d %q", resp.StatusCode, body)
	}
}
