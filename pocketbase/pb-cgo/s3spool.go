package main

// Склад свежих файлов на своём диске (10.11.2026).
//
// С 9.11.2026 хранилище Hetzner временами держит запись файла по 20–70 секунд,
// и все обращения к этому файлу в это время ждут и отпускаются разом. Замер
// 10.11: прямые чтения одного файла, начатые в 22:01:33, :38 и :43 обоими
// путями, получили первый байт в одну и ту же секунду 22:02:25; соединение и
// TLS при этом мгновенные, нагрузка от нас — три запроса в секунду. PocketBase
// бросал попытку через 15 секунд и начинал заново, человеку уходило «не
// удалось загрузить» (около 200 раз в сутки), а только что присланная картинка
// не открывалась у партнёра.
//
// Склад убирает хранилище с пути человека:
//   - запись файла до [maxPut] кладётся на диск, PocketBase сразу получает
//     «принято», а в хранилище файл досылается в фоне, сколько бы оно ни
//     тянуло и сколько бы раз ни отказало. Каждая досылка подписывается
//     заново: подпись живёт 15 минут, а отказ может длиться дольше;
//   - чтение файла, который лежит на складе, идёт с диска;
//   - прочитанное из хранилища (до [maxFetch]) запоминается на [keep], так
//     что повторные чтения аватарок и картинок в хранилище не ходят;
//   - недосланное со склада не выбрасывается никогда и переживает перезапуск.
//
// Составная загрузка (файлы от 6 МБ), список бакета и копирование идут в
// хранилище напрямую, как раньше. Имена файлов PocketBase неповторимы (в них
// случайный хвост), поэтому копия на складе не может устареть.
//
// Включается переменной окружения S3_SPOOL_DIR; без неё сборка ведёт себя
// по-прежнему.

import (
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Что склад помнит о файле.
type spoolMeta struct {
	// путь запроса: /бакет/ключ
	Path string `json:"path"`
	// полный адрес файла в хранилище
	URL  string `json:"url"`
	Size int64  `json:"size"`
	ETag string `json:"etag"`
	// когда файл принят или прочитан
	Modified time.Time `json:"modified"`
	// заголовки файла: тип, метки x-amz-meta-* и прочее, что отдаём при
	// чтении и шлём при досылке
	Headers map[string]string `json:"headers"`
	// ключ доступа и область — из подписи исходного запроса
	AccessKey string `json:"accessKey,omitempty"`
	Region    string `json:"region,omitempty"`
	// файл есть в хранилище: досылка прошла либо он оттуда и прочитан
	Stored   bool      `json:"stored"`
	StoredAt time.Time `json:"storedAt,omitempty"`
}

type s3Spool struct {
	dir   string
	retry *s3Retry
	// секрет хранилища для подписи досылок; пока пуст, склад записи не берёт
	secret atomic.Value
	// запись крупнее идёт в хранилище напрямую (PocketBase шлёт одним
	// запросом файлы до 6 МБ)
	maxPut int64
	// прочитанное крупнее не запоминаем
	maxFetch int64
	// сколько держим файл, который уже есть в хранилище
	keep time.Duration
	// потолок склада на диске; недосланное в него не входит
	maxBytes int64
	// срок одной досылки и прибавка за мегабайт
	uploadWait  time.Duration
	perMegabyte time.Duration
	// паузы между досылками; последняя повторяется
	retryPause []time.Duration
	logf       func(format string, args ...any)

	ctx    context.Context
	cancel context.CancelFunc
	// не больше восьми досылок разом
	slots chan struct{}

	mu sync.Mutex
	// файлы, которые сейчас досылаются
	busy map[string]bool
	// удалённые, пока досылка была в полёте: после неё убрать из хранилища
	gone map[string]*spoolMeta

	// счётчики для строки в журнале
	taken, served, sent atomic.Int64
}

func newS3Spool(dir string, retry *s3Retry) (*s3Spool, error) {
	for _, sub := range []string{"objects", "tmp"} {
		if err := os.MkdirAll(filepath.Join(dir, sub), 0o700); err != nil {
			return nil, err
		}
	}
	// недописанное при прошлом запуске
	if leftovers, err := os.ReadDir(filepath.Join(dir, "tmp")); err == nil {
		for _, entry := range leftovers {
			os.Remove(filepath.Join(dir, "tmp", entry.Name()))
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	spool := &s3Spool{
		dir:         dir,
		retry:       retry,
		maxPut:      8 << 20,
		maxFetch:    4 << 20,
		keep:        72 * time.Hour,
		maxBytes:    30 << 30,
		uploadWait:  120 * time.Second,
		perMegabyte: 2 * time.Second,
		retryPause:  []time.Duration{2 * time.Second, 5 * time.Second, 15 * time.Second, 30 * time.Second, time.Minute},
		logf:        log.Printf,
		ctx:         ctx,
		cancel:      cancel,
		slots:       make(chan struct{}, 8),
		busy:        map[string]bool{},
		gone:        map[string]*spoolMeta{},
	}
	spool.secret.Store("")
	return spool, nil
}

func (s *s3Spool) stop() { s.cancel() }

// Запрос к одному файлу: /бакет/ключ без параметров. Список бакета, части
// составной загрузки и копирование сюда не попадают.
func isObjectRequest(req *http.Request) bool {
	if req.URL.RawQuery != "" || req.Header.Get("X-Amz-Copy-Source") != "" {
		return false
	}
	path := strings.Trim(req.URL.Path, "/")
	return strings.Contains(path, "/") && !strings.HasSuffix(req.URL.Path, "/")
}

func (s *s3Spool) files(path string) (data, meta string) {
	sum := sha256.Sum256([]byte(path))
	name := hex.EncodeToString(sum[:])
	base := filepath.Join(s.dir, "objects", name[:2], name)
	return base + ".bin", base + ".json"
}

func (s *s3Spool) load(path string) (*spoolMeta, string, bool) {
	data, metaFile := s.files(path)
	raw, err := os.ReadFile(metaFile)
	if err != nil {
		return nil, "", false
	}
	meta := &spoolMeta{}
	if json.Unmarshal(raw, meta) != nil || meta.Path != path {
		return nil, "", false
	}
	if info, err := os.Stat(data); err != nil || info.Size() != meta.Size {
		return nil, "", false
	}
	return meta, data, true
}

func (s *s3Spool) saveMeta(meta *spoolMeta) error {
	_, metaFile := s.files(meta.Path)
	raw, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	tmp := metaFile + ".new"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, metaFile)
}

func (s *s3Spool) has(path string) bool {
	_, _, ok := s.load(path)
	return ok
}

func (s *s3Spool) isStored(path string) bool {
	meta, _, ok := s.load(path)
	return ok && meta.Stored
}

func (s *s3Spool) drop(path string) {
	data, metaFile := s.files(path)
	os.Remove(metaFile)
	os.Remove(data)
}

// Заголовки, которые принадлежат файлу, а не запросу.
func fileHeader(name string) bool {
	switch name = http.CanonicalHeaderKey(name); name {
	case "Content-Type", "Cache-Control", "Content-Disposition", "Content-Encoding", "Content-Language":
		return true
	}
	return strings.HasPrefix(http.CanonicalHeaderKey(name), "X-Amz-Meta-")
}

func keepFileHeaders(from http.Header) map[string]string {
	kept := map[string]string{}
	for name, values := range from {
		if fileHeader(name) && len(values) > 0 {
			kept[http.CanonicalHeaderKey(name)] = values[0]
		}
	}
	return kept
}

// Ключ доступа и область из подписи: «Credential=ключ/дата/область/s3/aws4_request».
func credentialOf(req *http.Request) (accessKey, region string) {
	auth := req.Header.Get("Authorization")
	at := strings.Index(auth, "Credential=")
	if at < 0 {
		return "", ""
	}
	parts := strings.Split(strings.SplitN(auth[at+len("Credential="):], ",", 2)[0], "/")
	if len(parts) < 3 {
		return "", ""
	}
	return parts[0], parts[2]
}

func spoolResponse(req *http.Request, code int, header http.Header, body io.ReadCloser, length int64) *http.Response {
	return &http.Response{
		Status:        fmt.Sprintf("%d %s", code, http.StatusText(code)),
		StatusCode:    code,
		Proto:         "HTTP/1.1",
		ProtoMajor:    1,
		ProtoMinor:    1,
		Header:        header,
		Body:          body,
		ContentLength: length,
		Request:       req,
	}
}

// Берёт ли склад запрос на себя. false — запрос идёт в хранилище как обычно.
func (s *s3Spool) handle(req *http.Request) (*http.Response, bool) {
	if !isObjectRequest(req) {
		return nil, false
	}
	switch req.Method {
	case http.MethodPut:
		return s.put(req)
	case http.MethodGet, http.MethodHead:
		return s.serve(req)
	case http.MethodDelete:
		s.forget(req.URL.Path)
	}
	return nil, false
}

// Запись: файл на диск, PocketBase — «принято», досылка в фоне.
func (s *s3Spool) put(req *http.Request) (*http.Response, bool) {
	secret, _ := s.secret.Load().(string)
	accessKey, region := credentialOf(req)
	if secret == "" || accessKey == "" || req.GetBody == nil || req.Body == nil ||
		req.ContentLength <= 0 || req.ContentLength > s.maxPut {
		return nil, false
	}
	// Не вышло положить на диск — запрос идёт в хранилище напрямую, с телом
	// с начала.
	giveBack := func(tmp *os.File, why error) (*http.Response, bool) {
		if tmp != nil {
			tmp.Close()
			os.Remove(tmp.Name())
		}
		s.logf("[s3-spool] %s: на склад не лёг (%v), пишу в хранилище напрямую", req.URL.Path, why)
		if body, err := req.GetBody(); err == nil {
			req.Body = body
		}
		return nil, false
	}
	tmp, err := os.CreateTemp(filepath.Join(s.dir, "tmp"), "put-*")
	if err != nil {
		return giveBack(nil, err)
	}
	sum := md5.New()
	size, err := io.Copy(io.MultiWriter(tmp, sum), io.LimitReader(req.Body, s.maxPut+1))
	req.Body.Close()
	if err == nil && size != req.ContentLength {
		err = fmt.Errorf("пришло %d байт из %d", size, req.ContentLength)
	}
	if err == nil {
		err = tmp.Sync()
	}
	if err != nil {
		return giveBack(tmp, err)
	}
	tmp.Close()

	meta := &spoolMeta{
		Path:      req.URL.Path,
		URL:       req.URL.String(),
		Size:      size,
		ETag:      `"` + hex.EncodeToString(sum.Sum(nil)) + `"`,
		Modified:  time.Now().UTC().Truncate(time.Second),
		Headers:   keepFileHeaders(req.Header),
		AccessKey: accessKey,
		Region:    region,
	}
	data, _ := s.files(meta.Path)
	if err = os.MkdirAll(filepath.Dir(data), 0o700); err == nil {
		err = os.Rename(tmp.Name(), data)
	}
	if err == nil {
		err = s.saveMeta(meta)
	}
	if err != nil {
		os.Remove(tmp.Name())
		s.drop(meta.Path)
		return giveBack(nil, err)
	}
	s.mu.Lock()
	delete(s.gone, meta.Path)
	s.mu.Unlock()
	s.taken.Add(1)
	s.startUpload(meta.Path)
	return spoolResponse(req, http.StatusOK, http.Header{"Etag": {meta.ETag}}, http.NoBody, 0), true
}

// Чтение со склада, целиком или куском.
func (s *s3Spool) serve(req *http.Request) (*http.Response, bool) {
	meta, data, ok := s.load(req.URL.Path)
	if !ok {
		return nil, false
	}
	header := http.Header{}
	for name, value := range meta.Headers {
		header.Set(name, value)
	}
	header.Set("Etag", meta.ETag)
	header.Set("Last-Modified", meta.Modified.UTC().Format(http.TimeFormat))
	header.Set("Accept-Ranges", "bytes")

	from, to, partial := int64(0), meta.Size-1, false
	if asked := req.Header.Get("Range"); asked != "" && meta.Size > 0 {
		if a, b, ok := parseRange(asked, meta.Size); ok {
			from, to, partial = a, b, true
		}
	}
	length := to - from + 1
	header.Set("Content-Length", strconv.FormatInt(length, 10))
	code := http.StatusOK
	if partial {
		code = http.StatusPartialContent
		header.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", from, to, meta.Size))
	}
	s.served.Add(1)
	if req.Method == http.MethodHead {
		return spoolResponse(req, code, header, http.NoBody, length), true
	}
	file, err := os.Open(data)
	if err != nil {
		return nil, false
	}
	body := struct {
		io.Reader
		io.Closer
	}{io.NewSectionReader(file, from, length), file}
	return spoolResponse(req, code, header, body, length), true
}

// «bytes=2-5», «bytes=7-», «bytes=-3». Иное — отдаём файл целиком.
func parseRange(asked string, size int64) (from, to int64, ok bool) {
	spec, found := strings.CutPrefix(asked, "bytes=")
	if !found || strings.Contains(spec, ",") {
		return 0, 0, false
	}
	first, last, found := strings.Cut(spec, "-")
	if !found {
		return 0, 0, false
	}
	if first == "" {
		tail, err := strconv.ParseInt(last, 10, 64)
		if err != nil || tail <= 0 {
			return 0, 0, false
		}
		if tail > size {
			tail = size
		}
		return size - tail, size - 1, true
	}
	from, err := strconv.ParseInt(first, 10, 64)
	if err != nil || from < 0 || from >= size {
		return 0, 0, false
	}
	to = size - 1
	if last != "" {
		end, err := strconv.ParseInt(last, 10, 64)
		if err != nil || end < from {
			return 0, 0, false
		}
		if end < to {
			to = end
		}
	}
	return from, to, true
}

// Удаление: убрать со склада; если досылка ещё не дошла, после неё убрать
// файл и из хранилища. Сам запрос удаления идёт в хранилище как обычно.
func (s *s3Spool) forget(path string) {
	meta, _, ok := s.load(path)
	if !ok {
		return
	}
	if !meta.Stored {
		s.mu.Lock()
		busy := s.busy[path]
		if busy {
			s.gone[path] = meta
		}
		s.mu.Unlock()
	}
	s.drop(path)
}

// Запомнить прочитанное из хранилища: тело ответа по дороге пишется на склад.
func (s *s3Spool) remember(req *http.Request, resp *http.Response) *http.Response {
	if req.Method != http.MethodGet || resp == nil || resp.StatusCode != http.StatusOK ||
		req.Header.Get("Range") != "" || !isObjectRequest(req) ||
		resp.ContentLength <= 0 || resp.ContentLength > s.maxFetch {
		return resp
	}
	tmp, err := os.CreateTemp(filepath.Join(s.dir, "tmp"), "get-*")
	if err != nil {
		return resp
	}
	meta := &spoolMeta{
		Path:     req.URL.Path,
		URL:      req.URL.String(),
		Size:     resp.ContentLength,
		ETag:     resp.Header.Get("Etag"),
		Modified: time.Now().UTC().Truncate(time.Second),
		Headers:  keepFileHeaders(resp.Header),
		Stored:   true,
		StoredAt: time.Now().UTC(),
	}
	if seen, err := http.ParseTime(resp.Header.Get("Last-Modified")); err == nil {
		meta.Modified = seen.UTC()
	}
	resp.Body = &rememberingBody{ReadCloser: resp.Body, spool: s, tmp: tmp, meta: meta}
	return resp
}

type rememberingBody struct {
	io.ReadCloser
	spool *s3Spool
	tmp   *os.File
	meta  *spoolMeta
	seen  int64
	done  bool
}

func (b *rememberingBody) Read(p []byte) (int, error) {
	n, err := b.ReadCloser.Read(p)
	if n > 0 && b.tmp != nil {
		if _, werr := b.tmp.Write(p[:n]); werr != nil {
			b.discard()
		}
		b.seen += int64(n)
	}
	if err == io.EOF {
		b.finish()
	}
	return n, err
}

func (b *rememberingBody) Close() error {
	b.finish()
	return b.ReadCloser.Close()
}

func (b *rememberingBody) discard() {
	if b.tmp != nil {
		b.tmp.Close()
		os.Remove(b.tmp.Name())
		b.tmp = nil
	}
}

// Кладём на склад, только если тело дочитано до конца.
func (b *rememberingBody) finish() {
	if b.done {
		return
	}
	b.done = true
	if b.tmp == nil || b.seen != b.meta.Size {
		b.discard()
		return
	}
	name := b.tmp.Name()
	b.tmp.Close()
	b.tmp = nil
	// Пока читали, файл могли записать или удалить: своё не затираем.
	if b.spool.has(b.meta.Path) {
		os.Remove(name)
		return
	}
	data, _ := b.spool.files(b.meta.Path)
	if os.MkdirAll(filepath.Dir(data), 0o700) != nil || os.Rename(name, data) != nil {
		os.Remove(name)
		return
	}
	if b.spool.saveMeta(b.meta) != nil {
		os.Remove(data)
	}
}

// ── досылка в хранилище ──────────────────────────────────────────────────────

func (s *s3Spool) startUpload(path string) {
	s.mu.Lock()
	if s.busy[path] {
		s.mu.Unlock()
		return
	}
	s.busy[path] = true
	s.mu.Unlock()
	go func() {
		defer func() {
			s.mu.Lock()
			delete(s.busy, path)
			s.mu.Unlock()
		}()
		s.upload(path)
	}()
}

func (s *s3Spool) pauseBefore(attempt int) time.Duration {
	if len(s.retryPause) == 0 {
		return time.Second
	}
	if attempt-1 < len(s.retryPause) {
		return s.retryPause[attempt-1]
	}
	return s.retryPause[len(s.retryPause)-1]
}

// Досылает файл, пока хранилище его не примет. Отказ не теряет файл: он
// лежит на складе и читается оттуда.
func (s *s3Spool) upload(path string) {
	select {
	case s.slots <- struct{}{}:
		defer func() { <-s.slots }()
	case <-s.ctx.Done():
		return
	}
	began := time.Now()
	for attempt := 1; ; attempt++ {
		meta, data, ok := s.load(path)
		if !ok || meta.Stored {
			break // удалён или уже дослан
		}
		err := s.send(http.MethodPut, meta, data, attempt)
		if err == nil {
			// Перечитываем: пока досылали, файл могли удалить.
			if fresh, _, still := s.load(path); still && !fresh.Stored {
				fresh.Stored, fresh.StoredAt = true, time.Now().UTC()
				s.saveMeta(fresh)
			}
			s.sent.Add(1)
			if attempt > 1 || time.Since(began) > 10*time.Second {
				s.logf("[s3-spool] %s: дослан с попытки %d за %s", path, attempt, time.Since(began).Round(time.Second))
			}
			break
		}
		if s.ctx.Err() != nil {
			return
		}
		s.logf("[s3-spool] %s: досылка %d не прошла (%v), файл на складе, повторю", path, attempt, err)
		select {
		case <-s.ctx.Done():
			return
		case <-time.After(s.pauseBefore(attempt)):
		}
	}
	// Файл удалили, пока он досылался: в хранилище он лишний.
	s.removeFromStore(path)
}

func (s *s3Spool) removeFromStore(path string) {
	s.mu.Lock()
	target := s.gone[path]
	delete(s.gone, path)
	s.mu.Unlock()
	if target == nil {
		return
	}
	for attempt := 1; attempt <= 3; attempt++ {
		if err := s.send(http.MethodDelete, target, "", attempt); err == nil {
			return
		}
		select {
		case <-s.ctx.Done():
			return
		case <-time.After(s.pauseBefore(attempt)):
		}
	}
	s.logf("[s3-spool] %s: удалён до досылки, но из хранилища убрать не вышло", path)
}

// Один запрос в хранилище со свежей подписью. Пути чередуются: нечётная
// попытка основным, чётная запасным.
func (s *s3Spool) send(method string, meta *spoolMeta, data string, attempt int) error {
	secret, _ := s.secret.Load().(string)
	if secret == "" {
		return errors.New("нет секрета хранилища")
	}
	wait := s.uploadWait + time.Duration(meta.Size*int64(s.perMegabyte)/(1<<20))
	ctx, cancel := context.WithTimeout(s.ctx, wait)
	defer cancel()

	var body io.Reader
	if method == http.MethodPut {
		file, err := os.Open(data)
		if err != nil {
			return err
		}
		defer file.Close()
		body = file
	}
	req, err := http.NewRequestWithContext(ctx, method, meta.URL, body)
	if err != nil {
		return err
	}
	if method == http.MethodPut {
		req.ContentLength = meta.Size
		for name, value := range meta.Headers {
			req.Header.Set(name, value)
		}
	}
	req.Header.Set("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD")
	req.Header.Set("Accept-Encoding", "identity")
	signS3(req, meta.AccessKey, secret, meta.Region, time.Now().UTC())

	path := 1
	if attempt%2 == 0 {
		path = 2
	}
	resp, err := s.retry.transportFor(path).RoundTrip(req)
	if err != nil {
		return err
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	resp.Body.Close()
	if resp.StatusCode >= 300 && !(method == http.MethodDelete && resp.StatusCode == http.StatusNotFound) {
		return fmt.Errorf("ответ %d", resp.StatusCode)
	}
	return nil
}

// После запуска: дослать то, что не успело уйти до перезапуска.
func (s *s3Spool) resume() {
	waiting := 0
	s.walk(func(meta *spoolMeta, _ int64) {
		if !meta.Stored {
			waiting++
			s.startUpload(meta.Path)
		}
	})
	if waiting > 0 {
		s.logf("[s3-spool] после запуска досылается файлов: %d", waiting)
	}
}

func (s *s3Spool) walk(visit func(meta *spoolMeta, size int64)) {
	filepath.WalkDir(filepath.Join(s.dir, "objects"), func(name string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() || !strings.HasSuffix(name, ".json") {
			return nil
		}
		raw, err := os.ReadFile(name)
		if err != nil {
			return nil
		}
		meta := &spoolMeta{}
		if json.Unmarshal(raw, meta) != nil || meta.Path == "" {
			return nil
		}
		visit(meta, meta.Size)
		return nil
	})
}

// Уборка: файлы, которые уже есть в хранилище, живут на складе [keep] и в
// пределах [maxBytes]. Недосланное не трогаем.
func (s *s3Spool) sweep() {
	type item struct {
		path string
		size int64
		at   time.Time
	}
	var stored []item
	var total, waiting int64
	now := time.Now()
	s.walk(func(meta *spoolMeta, size int64) {
		if !meta.Stored {
			waiting++
			return
		}
		if now.Sub(meta.StoredAt) >= s.keep {
			s.drop(meta.Path)
			return
		}
		stored = append(stored, item{meta.Path, size, meta.StoredAt})
		total += size
	})
	sort.Slice(stored, func(i, j int) bool { return stored[i].at.Before(stored[j].at) })
	for _, it := range stored {
		if total <= s.maxBytes {
			break
		}
		s.drop(it.path)
		total -= it.size
	}
	s.logf("[s3-spool] принято %d, отдано с диска %d, дослано %d; на складе %d МБ, ждут досылки %d",
		s.taken.Swap(0), s.served.Swap(0), s.sent.Swap(0), total>>20, waiting)
}

// Раз в десять минут уборка и строка в журнал.
func (s *s3Spool) run() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			s.sweep()
		}
	}
}

// ── подпись запроса (AWS Signature Version 4) ────────────────────────────────

// Подписывает запрос так же, как клиент S3 в PocketBase: в подпись входят
// host, content-type, range и все x-amz-*.
func signS3(req *http.Request, accessKey, secret, region string, now time.Time) {
	const stamp = "20060102T150405Z"
	if req.Header.Get("X-Amz-Content-Sha256") == "" {
		req.Header.Set("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD")
	}
	req.Header.Set("X-Amz-Date", now.Format(stamp))
	day := now.Format("20060102")

	headers := map[string]string{"host": req.URL.Host}
	for name, values := range req.Header {
		low := strings.ToLower(name)
		if low == "content-type" || low == "range" || strings.HasPrefix(low, "x-amz-") {
			trimmed := make([]string, len(values))
			for i, v := range values {
				trimmed[i] = strings.Join(strings.Fields(v), " ")
			}
			headers[low] = strings.Join(trimmed, ",")
		}
	}
	names := make([]string, 0, len(headers))
	for name := range headers {
		names = append(names, name)
	}
	sort.Strings(names)
	var canonical strings.Builder
	for _, name := range names {
		canonical.WriteString(name + ":" + headers[name] + "\n")
	}
	signed := strings.Join(names, ";")

	request := strings.Join([]string{
		req.Method,
		escapeS3Path(req.URL.Path),
		escapeS3Query(req.URL.Query()),
		canonical.String(),
		signed,
		req.Header.Get("X-Amz-Content-Sha256"),
	}, "\n")
	scope := day + "/" + region + "/s3/aws4_request"
	hashed := sha256.Sum256([]byte(request))
	toSign := "AWS4-HMAC-SHA256\n" + now.Format(stamp) + "\n" + scope + "\n" + hex.EncodeToString(hashed[:])

	key := hmacSum([]byte("AWS4"+secret), day)
	key = hmacSum(key, region)
	key = hmacSum(key, "s3")
	key = hmacSum(key, "aws4_request")
	req.Header.Set("Authorization", fmt.Sprintf("AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
		accessKey, scope, signed, hex.EncodeToString(hmacSum(key, toSign))))
}

func hmacSum(key []byte, text string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(text))
	return mac.Sum(nil)
}

func escapeS3(text string) string {
	var out strings.Builder
	for i := 0; i < len(text); i++ {
		c := text[i]
		if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '.' || c == '_' || c == '~' {
			out.WriteByte(c)
		} else {
			fmt.Fprintf(&out, "%%%02X", c)
		}
	}
	return out.String()
}

func escapeS3Path(path string) string {
	parts := strings.Split(path, "/")
	for i, part := range parts {
		parts[i] = escapeS3(part)
	}
	return strings.Join(parts, "/")
}

func escapeS3Query(values map[string][]string) string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var out []string
	for _, key := range keys {
		for _, value := range values[key] {
			out = append(out, escapeS3(key)+"="+escapeS3(value))
		}
	}
	return strings.Join(out, "&")
}
