# ios/certs

Пусто по замыслу. Приватный ключ iOS distribution-сертификата **в git не
хранится** — репозиторий публичный.

## Где ключ теперь

Codemagic → App settings → Environment variables → **`CERTIFICATE_PRIVATE_KEY`**
(значение = PEM приватного ключа, флаг **Secure**). Скрипт подписи в
`codemagic.yaml` читает его как `--certificate-key @env:CERTIFICATE_PRIVATE_KEY`.

Ключ **постоянный**: fetch-signing-files под ним переиспользует ОДИН
distribution-сертификат каждую сборку (не плодит новые → не упирается в лимит
Apple → нет «No Accounts» / «No profiles for com.togetherly.love»). Паттерн
уровня Fastlane Match, только хранилище подписи — не git, а секреты Codemagic.

## Если ключ меняется / скомпрометирован

1. Отозвать старый сертификат: Apple Developer → Certificates → Revoke.
2. Сгенерировать новый приватный ключ, обновить `CERTIFICATE_PRIVATE_KEY` в Codemagic.
3. Следующая сборка заведёт новый distribution-сертификат под новым ключом.
