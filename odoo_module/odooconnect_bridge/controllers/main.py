import html
import json
import logging
import secrets
import urllib.parse

from odoo import http
from odoo.http import request

_logger = logging.getLogger(__name__)

CALLBACK_SCHEME = "odooconnect"
CODE_TTL_SECONDS = 120
HANDOFF_MODEL = "odooconnect.oauth.handoff"


class OdooConnectBridge(http.Controller):
    """Bridges a successful Odoo session into an API key the iOS app can store.

    Flow:
      1. GET  /api/odooconnect/oauth_complete  (auth=user)
         Renders a same-origin, CSRF-protected POST form. It mints NOTHING,
         so the GET has no side effect and cannot be CSRF-forged into creating
         API keys.
      2. POST /api/odooconnect/oauth_mint      (auth=user, CSRF-protected)
         Mints a fresh `rpc` API key, stores a single-use handoff keyed by
         sha256(code) in a sudo-only model, and bounces to the app via the
         custom URL scheme.
      3. POST /api/odooconnect/oauth_exchange  (auth=public)
         Redeems the one-time code for the API key over HTTPS.

    The custom-scheme callback carries only a one-time code; the key never
    appears in a browser/custom-scheme URL and is never persisted in plain
    config storage.
    """

    @http.route(
        "/api/odooconnect/oauth_complete",
        type="http",
        auth="user",
        csrf=False,
        methods=["GET"],
        save_session=True,
    )
    def oauth_complete(self, **kwargs):
        state = kwargs.get("state")
        if not state:
            return self._error_page("OAuth-State fehlt. Bitte die Anmeldung aus der App neu starten.")
        # No side effect here — just render a same-origin form whose CSRF
        # token a cross-site attacker cannot read (same-origin policy), so
        # only this page can drive the key-minting POST below.
        token = request.csrf_token(time_limit=600)
        return self._mint_form_page(state=state, csrf_token=token)

    @http.route(
        "/api/odooconnect/oauth_mint",
        type="http",
        auth="user",
        methods=["POST"],
        save_session=True,
    )
    def oauth_mint(self, **kwargs):
        # csrf defaults to True for a type="http" POST route, so Odoo's
        # dispatcher has already rejected any request lacking a valid,
        # session-bound csrf_token before reaching this handler.
        user = request.env.user
        state = kwargs.get("state")
        if not state:
            return self._error_page("OAuth-State fehlt. Bitte die Anmeldung aus der App neu starten.")

        try:
            api_key_record = self._generate_key(scope="rpc", name="OdooConnect iOS")
        except Exception as exc:  # noqa: BLE001 -- show the user a real error
            _logger.exception("OdooConnect bridge: API key generation failed")
            return self._error_page(f"API-Key konnte nicht erzeugt werden: {exc}")

        # _generate returns the plaintext key on Odoo 17+; older versions
        # returned a record. Stay defensive.
        api_key = api_key_record
        if not isinstance(api_key, str):
            api_key = getattr(api_key_record, "key", None) or str(api_key_record)
        if not api_key:
            _logger.error("OdooConnect bridge: empty API key returned by _generate")
            return self._error_page("API-Key war leer (interner Fehler).")

        code = secrets.token_urlsafe(32)
        request.env[HANDOFF_MODEL].sudo().stash(
            code=code,
            api_key=api_key,
            uid=user.id,
            login=user.login,
            database=request.env.cr.dbname,
            ttl=CODE_TTL_SECONDS,
        )

        callback = f"{CALLBACK_SCHEME}://oauth-callback?" + urllib.parse.urlencode(
            {
                "code": code,
                "state": state,
            }
        )
        _logger.info(
            "OdooConnect bridge minted one-time OAuth code for user %s (uid=%s, db=%s)",
            user.login,
            user.id,
            request.env.cr.dbname,
        )
        return self._success_page(callback)

    @http.route(
        "/api/odooconnect/oauth_exchange",
        type="http",
        auth="public",
        csrf=False,
        methods=["POST"],
        save_session=False,
    )
    def oauth_exchange(self, **kwargs):
        try:
            body = json.loads(request.httprequest.get_data(as_text=True) or "{}")
        except ValueError:
            return self._json_error("Ungueltige Anfrage.", status=400)

        code = body.get("code")
        if not isinstance(code, str) or not code:
            return self._json_error("OAuth-Code fehlt.", status=400)

        stored = request.env[HANDOFF_MODEL].sudo().redeem(code=code)
        if not stored:
            return self._json_error(
                "OAuth-Code ist ungueltig, abgelaufen oder wurde bereits verwendet.",
                status=404,
            )

        return self._json_response(
            {
                "api_key": stored["api_key"],
                "uid": stored["uid"],
                "login": stored["login"],
                "database": stored["database"],
            }
        )

    # -- helpers --

    def _generate_key(self, scope, name):
        """Calls `res.users.apikeys._generate(...)` across Odoo versions."""
        api_keys = request.env["res.users.apikeys"].sudo()
        try:
            return api_keys._generate(scope, name, False)
        except TypeError:
            try:
                return api_keys._generate(scope, name, expiration_date=False)
            except TypeError:
                return api_keys._generate(scope, name)

    def _mint_form_page(self, state: str, csrf_token: str):
        safe_state = html.escape(state, quote=True)
        safe_token = html.escape(csrf_token, quote=True)
        # `action="oauth_mint"` is relative to /api/odooconnect/oauth_complete,
        # so it resolves to /api/odooconnect/oauth_mint and stays correct
        # behind a reverse-proxy path prefix.
        body = (
            "<!DOCTYPE html>"
            "<html lang='de'><head>"
            "<meta charset='utf-8'>"
            "<title>OdooCompanion</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            "</head>"
            "<body style=\"font-family:-apple-system,system-ui,sans-serif;"
            "padding:32px;text-align:center;color:#1d1d1f;background:#fff\">"
            "<h2 style='margin:0 0 12px;font-weight:700'>Anmeldung abschliessen</h2>"
            "<p style='margin:0 0 18px;color:#444'>Du wirst zurueck zur App geleitet...</p>"
            "<form id='mint' method='post' action='oauth_mint'>"
            f"<input type='hidden' name='csrf_token' value='{safe_token}'>"
            f"<input type='hidden' name='state' value='{safe_state}'>"
            "<button type='submit' style='display:inline-block;padding:12px 22px;"
            "background:#F87120;color:#fff;border:0;text-decoration:none;"
            "border-radius:14px;font-weight:600;font-size:16px'>Weiter zur App</button>"
            "</form>"
            "<script>document.getElementById('mint').submit();</script>"
            "</body></html>"
        )
        return request.make_response(
            body,
            headers=[
                ("Content-Type", "text/html; charset=utf-8"),
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma", "no-cache"),
                ("X-Frame-Options", "DENY"),
                ("Content-Security-Policy", "frame-ancestors 'none'"),
                ("Referrer-Policy", "no-referrer"),
            ],
        )

    def _success_page(self, callback_url: str):
        safe_callback = html.escape(callback_url, quote=True)
        # Build the JS string from a properly escaped JSON literal rather than
        # Python repr(), so a future change to callback_url can't break out of
        # the script context.
        js_callback = json.dumps(callback_url)
        body = (
            "<!DOCTYPE html>"
            "<html lang='de'><head>"
            "<meta charset='utf-8'>"
            "<title>OdooCompanion</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<meta http-equiv='refresh' content='0;url={safe_callback}'>"
            "</head>"
            "<body style=\"font-family:-apple-system,system-ui,sans-serif;"
            "padding:32px;text-align:center;color:#1d1d1f;background:#fff\">"
            "<h2 style='margin:0 0 12px;font-weight:700'>Erfolg</h2>"
            "<p style='margin:0 0 18px;color:#444'>Du wirst zurueck zur App geleitet...</p>"
            f"<p style='margin:0 0 18px'><a href='{safe_callback}' "
            "style='display:inline-block;padding:12px 22px;background:#F87120;"
            "color:#fff;text-decoration:none;border-radius:14px;font-weight:600'>"
            "Zur App zurueck</a></p>"
            f"<script>(function(){{ try {{ window.location.replace({js_callback}); }}"
            f"catch(e){{}} setTimeout(function(){{ window.location.href = {js_callback}; }}, 200); }})();</script>"
            "</body></html>"
        )
        return request.make_response(
            body,
            headers=[
                ("Content-Type", "text/html; charset=utf-8"),
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma", "no-cache"),
            ],
        )

    def _error_page(self, message: str):
        body = (
            "<!DOCTYPE html>"
            "<html lang='de'><head>"
            "<meta charset='utf-8'>"
            "<title>OdooCompanion</title>"
            "</head>"
            "<body style=\"font-family:-apple-system,system-ui,sans-serif;"
            "padding:32px;text-align:center;color:#1d1d1f;background:#fff\">"
            "<h2 style='color:#EF4444;margin:0 0 12px'>Fehler</h2>"
            f"<p style='margin:0;color:#444'>{html.escape(message)}</p>"
            "</body></html>"
        )
        return request.make_response(
            body,
            status=500,
            headers=[
                ("Content-Type", "text/html; charset=utf-8"),
                ("Cache-Control", "no-store"),
            ],
        )

    def _json_response(self, payload, status=200):
        return request.make_response(
            json.dumps(payload),
            status=status,
            headers=[
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma", "no-cache"),
            ],
        )

    def _json_error(self, message, status=400):
        return self._json_response({"error": message}, status=status)
