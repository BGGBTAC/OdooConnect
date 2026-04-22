# OdooConnect

Native iOS 26 Universal‑App (iPhone + iPad) für Odoo 19 Enterprise
(Odoo.sh / Odoo SaaS). Verbindet sich direkt per JSON‑RPC mit dem Odoo‑Server.

## Funktionen

- **Dashboard**: Monatsumsatz, offene Angebote / Bestellungen, offene
  Forderungen, Umsatzverlauf der letzten 8 Wochen (Swift Charts).
  Server‑seitig aggregiert via `read_group`.
- **Angebote**: Liste mit Suche, Erstellen + Bearbeiten lokaler
  Entwürfe, Detailansicht
- **Bestellungen**: Liste mit Suche und Detail; Apple Pencil
  Unterschrift wird als `ir.attachment` an die Bestellung gehängt
- **Rechnungen**: Liste mit Suche und Detail mit Zahlungsstatus
- **Offline‑Drafts**: SwiftData persistiert lokal; ein Outbox‑Actor
  pusht beim Online‑Werden automatisch nach Odoo. Idempotent via
  `client_order_ref`, max 5 Retries pro Draft, manueller
  Re‑Sync in den Einstellungen.
- **Push‑Notifications**: `BGAppRefreshTask` wacht ~alle 15 Min auf
  und prüft auf neue bestätigte Aufträge → lokale Notification
- **Multi‑Device**: Adaptive `TabView` wird auf iPad zur Sidebar
- **Multi‑Currency**: Beträge werden in der Beleg‑Währung
  angezeigt; Defaults aus `res.company.currency_id`
- **Sichere Auth**: API‑Key im Keychain (`ThisDeviceOnly`),
  keine Passwörter auf dem Gerät, kein iCloud‑Sync

## Voraussetzungen

- Xcode 26 (iOS 26 SDK)
- macOS 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Odoo 19 Enterprise mit aktivem API‑Key
  (Einstellungen → Benutzer → Konto‑Sicherheit → API‑Keys)

## Projekt generieren

```bash
xcodegen generate
open OdooConnect.xcodeproj
```

## Architektur

```
OdooConnect/
├── OdooConnectApp.swift            # @main, ModelContainer, BGTask register
├── Core/
│   ├── Networking/
│   │   ├── OdooClient.swift        # actor; JSON-RPC, search_read, read_group
│   │   ├── OdooError.swift
│   │   └── JSON.swift              # JSON-Value + Many2One Decoder
│   ├── Auth/
│   │   ├── AuthManager.swift       # @Observable; Keychain restore + company
│   │   └── KeychainStore.swift     # SecItemUpdate, ThisDeviceOnly
│   ├── Models/                     # Partner, Product, SaleOrder, Invoice,
│   │                               # Company, Currency
│   ├── Persistence/
│   │   ├── DraftQuote.swift        # @Model: DraftQuote + DraftLine
│   │   ├── Connectivity.swift      # NWPathMonitor → AsyncStream
│   │   ├── OutboxProcessor.swift   # @ModelActor; idempotent push
│   │   └── DraftSync.swift         # @MainActor coordinator
│   └── Notifications/
│       └── OrderWatcher.swift      # BGAppRefresh + UNNotification
└── Features/
    ├── Root/RootView.swift         # TabView .sidebarAdaptable
    ├── Auth/LoginView.swift
    ├── Dashboard/                  # Cards + Swift Charts
    ├── Quotes/                     # Liste + Editor + Pickers
    ├── Orders/                     # Liste + Detail + SignatureSheet
    ├── Invoices/                   # Liste + Detail
    └── Settings/                   # Verbindung, Currency, Sync, Notif
```

### Odoo API

Alle Aufrufe gehen über `POST {baseURL}/jsonrpc`:

- `common.authenticate(db, login, api_key, {})` → UID
- `object.execute_kw(db, uid, api_key, model, method, args, kwargs)`
  für `search_read`, `search_count`, `read_group`, `create`, `write`

### Offline‑Sync‑Pipeline

1. `QuoteEditorView` schreibt `DraftQuote` in SwiftData → Status `pending`
2. `DraftSync` triggert `OutboxProcessor.process(client:)`
3. `OutboxProcessor` (eigener `@ModelActor`):
   - sucht in Odoo nach `client_order_ref = draft.id` (Idempotenz)
   - falls vorhanden → übernimmt Remote‑ID, löscht lokal
   - sonst → `sale.order.create`, löscht lokal
   - bei Fehler → Status `failed`, `attempts++`, Retry bis Max 5
4. `Connectivity` (NWPathMonitor) triggert Sync bei Online‑Wechsel

### Bekannte Limits

- Push ohne eigenen Server → BG‑Polling alle ~15 Min (System‑Drift)
- Dashboard‑Aggregate gehen über die Company‑Default‑Währung; bei
  Mehrwährungs‑Belegen ist der Summenwert grob. Saubere Lösung:
  `read_group` nach `currency_id` → für später
- Editor unterstützt keine Discounts / Steuern; Odoo wendet
  Default‑Steuern via `onchange` an

### Roadmap

- [ ] String Catalog komplett befüllen + EN‑Übersetzung
- [ ] Discounts, Steuern, Versanddetails im Editor
- [ ] Server‑Push via Odoo‑Bot (statt BG‑Polling)
- [ ] Conflict‑Detection bei parallelen Edits
