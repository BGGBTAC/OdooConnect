# OdooConnect

Native iOS 26 Universal‑App (iPhone + iPad) für Odoo 19 Enterprise
(Odoo.sh / Odoo SaaS). Verbindet sich direkt per JSON‑RPC mit dem Odoo‑Server.

## Funktionen

- **Dashboard**: Monatsumsatz, offene Angebote, offene Bestellungen,
  offene Forderungen, Umsatzverlauf der letzten 8 Wochen (Chart)
- **Angebote**: Liste, Erstellen (Kunde + Positionen), Detailansicht
- **Bestellungen**: Liste bestätigter Aufträge mit Positionen
- **Rechnungen**: Liste und Detail mit Zahlungsstatus
- **Multi‑Device**: Adaptive `TabView` wird auf iPad zur Sidebar
- **Sichere Auth**: API‑Key im Keychain, keine Passwörter auf dem Gerät

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
├── OdooConnectApp.swift            # App entry, injiziert AuthManager
├── Core/
│   ├── Networking/
│   │   ├── OdooClient.swift        # actor; JSON-RPC /jsonrpc, execute_kw
│   │   ├── OdooError.swift
│   │   └── JSON.swift              # JSON‑Value + Many2One Decoder
│   ├── Auth/
│   │   ├── AuthManager.swift       # @Observable, State + Keychain
│   │   └── KeychainStore.swift
│   └── Models/                     # Partner, Product, SaleOrder, Invoice
└── Features/
    ├── Root/RootView.swift         # TabView .sidebarAdaptable
    ├── Auth/LoginView.swift
    ├── Dashboard/                  # Cards + Swift Charts
    ├── Quotes/                     # Liste + Editor + Partner/Product Picker
    ├── Orders/                     # Liste + Detail
    ├── Invoices/                   # Liste + Detail
    └── Settings/SettingsView.swift
```

### Odoo API

Alle Aufrufe gehen über `POST {baseURL}/jsonrpc`:

- `common.authenticate(db, login, api_key, {})` → UID
- `object.execute_kw(db, uid, api_key, model, method, args, kwargs)`
  für `search_read`, `search_count`, `read_group`, `create`, `write`

### Weitere Ausbaustufen

- Offline‑Drafts via SwiftData + Outbox‑Queue
- Signatur per Apple Pencil auf Angebots‑Detailansicht (PKCanvas)
- Push‑Notifications für neue Bestellungen
