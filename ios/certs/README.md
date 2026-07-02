# ios/certs

`dist_cert_key.pem` — **постоянный** приватный RSA-ключ (2048), под который
Codemagic создаёт/переиспользует ОДИН iOS distribution-сертификат для подписи
App Store-сборок (см. `codemagic.yaml` → шаг «Set up code signing», флаг
`--certificate-key @file:ios/certs/dist_cert_key.pem`).

**Зачем в репо:** репозиторий приватный. Так CI не генерит новый ключ каждую
сборку (это плодило сертификаты и упиралось в лимит Apple → «No Accounts» /
«No profiles for com.togetherly.love»). Один ключ → один сертификат навсегда.
Паттерн уровня Fastlane Match (приватный git как хранилище подписи).

**Не удалять и не перегенерировать** без причины — иначе Codemagic заведёт ещё
один distribution-сертификат. Если ключ всё же меняется, старый сертификат стоит
отозвать в Apple Developer → Certificates.
