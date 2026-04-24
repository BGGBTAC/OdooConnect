# OdooConnect Bridge

Companion Odoo module for the OdooConnect iOS app. Adds a single endpoint
that converts a successful browser-based Odoo login (password or any
configured OAuth provider — Google, Microsoft, SAML, …) into a fresh API
key, then bounces the user back into the iOS app with a short-lived
one-time code. The app exchanges that code for the key over HTTPS.

## Why it exists

The iOS client uses API-key auth for all JSON-RPC calls. Without this
bridge, the user has to manually create an API key in Odoo and copy it
into the app on first launch. With the bridge installed, the user taps
**Über Browser anmelden** in the app, signs into Odoo (using whatever
mechanism their company configured), and the app receives a usable key after
an HTTPS code exchange without anyone touching
`Settings → My Profile → Account Security → API Keys`.

## Installation

1. Copy the `odooconnect_bridge` directory into your Odoo addons path
   (e.g. `~/odoo.sh/addons/`, `/mnt/extra-addons/`, or a Git-managed
   `custom-addons/` folder).
2. Restart Odoo (or refresh the addons list in `Apps → Update Apps List`
   if developer mode is on).
3. In the Odoo UI, go to **Apps**, search for "OdooConnect Bridge",
   and click **Install**.

The module has no UI — installation registers the
`/api/odooconnect/oauth_complete` and `/api/odooconnect/oauth_exchange`
HTTP routes.

## Optional: enable Google / Microsoft sign-in

If you want users to sign in with Google or Microsoft (instead of an
Odoo password) inside the in-app browser:

1. **Settings → General Settings → Integrations → OAuth Authentication** → enable
2. Add a provider:
   - **Google**: create an OAuth 2.0 Client ID at <https://console.cloud.google.com/>,
     authorized redirect URI `https://<your-odoo>/auth_oauth/signin`
   - **Microsoft Azure AD**: register an app at
     <https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps>,
     redirect URI same as above

Once a provider is enabled, the standard Odoo `/web/login` page shows the
"Sign in with Google" / "Sign in with Microsoft" button. The iOS bridge
flow uses that same login page, so no app changes are needed.

## Security notes

- The API key is named "OdooConnect iOS" and scope `rpc` so it is visible
  and revocable in **My Profile → Account Security → API Keys**.
- Keys are minted with `sudo()` because the standard `_generate` requires
  `bypass_create` permission, which most regular users don't have.
- Each successful sign-in creates a *new* key. Old keys remain valid
  until explicitly revoked. Recommend periodic cleanup.
- The custom URL scheme (`odooconnect://`) carries only a one-time code and
  state value. The API key itself is returned only by the HTTPS exchange
  endpoint and the code is deleted after first use.

## Compatible Odoo versions

Tested on Odoo 17, 18, 19. The `res.users.apikeys._generate(scope, name)`
internal API has been stable since Odoo 14.
