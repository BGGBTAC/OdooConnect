import html
import json
import logging
import secrets
import time
import urllib.parse

from odoo import http
from odoo.http import request

_logger = logging.getLogger(__name__)

CALLBACK_SCHEME = "odooconnect"
CODE_TTL_SECONDS = 120
CODE_PARAM_PREFIX = "odooconnect.oauth."


class OdooConnectBridge(http.Controller):
    """Bridges a successful Odoo session into an API key the iOS app can store.

    The custom-scheme callback intentionally carries only a one-time code and
    the original state value. The iOS app exchanges that code over HTTPS at
    /api/odooconnect/oauth_exchange, so the API key is never exposed in the
    browser URL or custom-scheme URL.
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
        self._store_code(
            code,
            {
                "api_key": api_key,
                "uid": user.id,
                "login": user.login,
                "database": request.env.cr.dbname,
                "expires_at": time.time() + CODE_TTL_SECONDS,
            },
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

        stored = self._pop_code(code)
        if not stored:
            return self._json_error("OAuth-Code ist ungueltig oder wurde bereits verwendet.", status=404)
        if float(stored.get("expires_at") or 0) < time.time():
            return self._json_error("OAuth-Code ist abgelaufen. Bitte Anmeldung erneut starten.", status=410)

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

    def _store_code(self, code, payload):
        self._cleanup_expired_codes()
        request.env["ir.config_parameter"].sudo().set_param(
            f"{CODE_PARAM_PREFIX}{code}",
            json.dumps(payload),
        )

    def _pop_code(self, code):
        params = request.env["ir.config_parameter"].sudo()
        record = params.search([("key", "=", f"{CODE_PARAM_PREFIX}{code}")], limit=1)
        if not record:
            return None
        raw = record.value
        record.unlink()
        try:
            return json.loads(raw or "{}")
        except ValueError:
            return None

    def _cleanup_expired_codes(self):
        params = request.env["ir.config_parameter"].sudo()
        records = params.search([("key", "like", f"{CODE_PARAM_PREFIX}%")])
        now = time.time()
        for record in records:
            try:
                payload = json.loads(record.value or "{}")
            except ValueError:
                record.unlink()
                continue
            if float(payload.get("expires_at") or 0) < now:
                record.unlink()

    def _success_page(self, callback_url: str):
        safe_callback = html.escape(callback_url, quote=True)
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
            f"<script>(function(){{ try {{ window.location.replace({callback_url!r}); }}"
            f"catch(e){{}} setTimeout(function(){{ window.location.href = {callback_url!r}; }}, 200); }})();</script>"
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
