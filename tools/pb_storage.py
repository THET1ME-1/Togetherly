"""Доступ к файлам PocketBase, где бы они ни лежали — на диске или в S3.

Зачем: `thumb_cache.py` и `widget_anim.py` открывали исходники прямо по пути
`pb_data/storage/<коллекция>/<запись>/<файл>`. После переезда хранилища в бакет
такого пути у новых файлов уже нет, и оба скрипта молча перестали бы работать:
у админки модерации пропали бы миниатюры, а «живое фото» виджета — кадры.

Здесь один вход для обоих: сперва диск (пока файлы там, ничего не меняется и
ничего не тормозит), при промахе — выкачка из бакета во временный файл.

Обратное действие тоже общее: `widget_anim` удаляет исходное видео после
раскадровки, и удалять его нужно там, где оно реально лежит — иначе в бакете
навсегда останутся мегабайты, ради которых всё и затевалось.
"""
import os
import shutil
import subprocess
import tempfile

STORE = "/opt/pocketbase/pb_data/storage"
BUCKET = "hz:togetherly"  # до 24.10.2026: hk:b86d5542-togetherly-storage
RCLONE = "/usr/local/bin/rclone"
MEDIA = "pbc_2708086759"
FETCH_TIMEOUT = 120


class Source:
    """Исходник записи. Используется как контекст: временное само убирается.

    with Source(rec_id, name) as src:
        if src.path: ...
    """

    def __init__(self, rec_id, name, collection=MEDIA):
        self.rec_id = rec_id
        self.name = name
        self.collection = collection
        self.path = None
        self.from_bucket = False
        self._tmpdir = None

    def key(self):
        return "%s/%s/%s" % (self.collection, self.rec_id, self.name)

    def open(self):
        local = os.path.join(STORE, self.collection, self.rec_id, self.name)
        if os.path.exists(local):
            self.path = local
            return self

        # На диске нет — значит хранилище уже в бакете. Тянем во временный файл.
        try:
            self._tmpdir = tempfile.mkdtemp(prefix="pbsrc_")
            dst = os.path.join(self._tmpdir, self.name)
            res = subprocess.run(
                [RCLONE, "copyto", BUCKET + "/" + self.key(), dst,
                 "--retries", "3", "--low-level-retries", "10"],
                capture_output=True, timeout=FETCH_TIMEOUT,
            )
            if res.returncode == 0 and os.path.exists(dst) and os.path.getsize(dst) > 0:
                self.path = dst
                self.from_bucket = True
            else:
                self.close()
        except Exception:
            self.close()
        return self

    def close(self):
        if self._tmpdir:
            shutil.rmtree(self._tmpdir, ignore_errors=True)
            self._tmpdir = None
        if self.from_bucket:
            self.path = None

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()
        return False


def remove_source(rec_id, name, collection=MEDIA):
    """Убрать исходник и с диска, и из бакета. Молча: файла может уже не быть."""
    local = os.path.join(STORE, collection, rec_id, name)
    try:
        os.remove(local)
    except OSError:
        pass
    try:
        subprocess.run(
            [RCLONE, "deletefile", "%s/%s/%s/%s" % (BUCKET, collection, rec_id, name),
             "--retries", "3"],
            capture_output=True, timeout=FETCH_TIMEOUT,
        )
    except Exception:
        pass
