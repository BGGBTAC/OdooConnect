import logging
import urllib.parse

from odoo import http
from odoo.http import request

_logger = logging.getLogger(__name__)

CALLBACK_SCHEME = "odooconnect"


class OdooConnectBridge(http.Controller):
    """Bridges a successful Odoo session into an API key the iOS app can store.

    Flow (iOS-side):
        1.  iOS opens https://<server>/api/odooconnect/oauth_complete inside
            ASWebAuthenticationSession.
        2.  Odoo's `auth='user'` machinery sees no session → bounces the
            user to /web/login (or /web/login/oauth) with the original
            URL preserved as `?redirect=`.
        3.  The user authenticates by any means Odoo supports (password,
            Google OAuth, Microsoft OAuth, SAML, …).
        4.  On success, Odoo follows the preserved redirect back here, now
            with a valid session cookie.
        5.  This controller mints a fresh API key for that user and returns
            an HTML page that JS-redirects to odooconnect://oauth-callback?…
        6.  ASWebAuthenticationSession captures the custom-scheme URL,
            closes itself, and hands the URL back to the iOS app.
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

        params = {
            "api_key": api_key,
            "uid": user.id,
            "login": user.login,
            "database": request.env.cr.dbname,
        }
        callback = f"{CALLBACK_SCHEME}://oauth-callback?" + urllib.parse.urlencode(params)
        _logger.info(
            "OdooConnect bridge minted API key for user %s (uid=%s, db=%s)",
            user.login, user.id, request.env.cr.dbname,
        )
        return self._success_page(callback)

    # -- helpers --

    def _generate_key(self, scope, name):
        """Calls `res.users.apikeys._generate(...)` in a way that survives
        Odoo's signature changes across versions:
            - 17.0:  _generate(scope, name)                     [2 args]
            - 17.0+: _generate(scope, name, expiration_date=None) [opt]
            - 18.0+: _generate(scope, name, expiration_date)    [required]

        We always pass `expiration_date=False` (= no expiration), and fall
        back to the 2-arg form on older builds via a TypeError catch.
        """
        api_keys = request.env["res.users.apikeys"].sudo()
        try:
            return api_keys._generate(scope, name, False)
        except TypeError:
            try:
                return api_keys._generate(scope, name, expiration_date=False)
            except TypeError:
                return api_keys._generate(scope, name)

    def _success_page(self, callback_url: str):
        # Three layers of redirect so the in-app browser absolutely fires
        # the custom scheme, regardless of how strict its JS or
        # meta-refresh policy is:
        #   1. immediate window.location.replace
        #   2. setTimeout fallback in case (1) is blocked
        #   3. plain anchor the user can tap
        body = (
            "<!DOCTYPE html>"
            "<html lang='de'><head>"
            "<meta charset='utf-8'>"
            "<title>OdooCompanion</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<meta http-equiv='refresh' content='0;url={callback_url}'>"
            "</head>"
            "<body style=\"font-family:-apple-system,system-ui,sans-serif;"
            "padding:32px;text-align:center;color:#1d1d1f;background:#fff\">"
            "<h2 style='margin:0 0 12px;font-weight:700'>Erfolg</h2>"
            "<p style='margin:0 0 18px;color:#444'>Du wirst zurück zur App geleitet…</p>"
            f"<p style='margin:0 0 18px'><a href='{callback_url}' "
            "style='display:inline-block;padding:12px 22px;background:#F87120;"
            "color:#fff;text-decoration:none;border-radius:14px;font-weight:600'>"
            "Zur App zurück</a></p>"
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
            f"<p style='margin:0;color:#444'>{message}</p>"
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
