import logging
import urllib.parse

from odoo import http
from odoo.http import request

_logger = logging.getLogger(__name__)

CALLBACK_SCHEME = "odooconnect"


class OdooConnectBridge(http.Controller):
    """Bridges a successful Odoo session into an API key the iOS app can store.

    Flow:
        1.  iOS opens https://<server>/web/login?redirect=/api/odooconnect/oauth_complete
            inside ASWebAuthenticationSession.
        2.  User authenticates by any means Odoo supports (password, Google
            OAuth, Microsoft OAuth, SAML, …).
        3.  After Odoo finishes the login, it follows the ?redirect= parameter
            and lands here while still bearing a valid session cookie.
        4.  This controller mints a fresh API key for that user and returns
            an HTML page that JS-redirects to odooconnect://oauth-callback?…
        5.  ASWebAuthenticationSession captures the custom-scheme URL,
            closes itself, and hands the URL back to the iOS app.
    """

    @http.route(
        "/api/odooconnect/oauth_complete",
        type="http",
        auth="user",
        csrf=False,
        methods=["GET"],
    )
    def oauth_complete(self, **kwargs):
        user = request.env.user
        api_key = request.env["res.users.apikeys"].sudo()._generate(
            scope="rpc",
            name="OdooConnect iOS",
        )
        # _generate returns the plaintext key on Odoo 17+; older versions
        # returned a record. Stay defensive.
        if not isinstance(api_key, str):
            api_key = getattr(api_key, "key", None) or str(api_key)

        params = {
            "api_key": api_key,
            "uid": user.id,
            "login": user.login,
            "database": request.env.cr.dbname,
        }
        callback = f"{CALLBACK_SCHEME}://oauth-callback?" + urllib.parse.urlencode(params)
        _logger.info("OdooConnect bridge minted API key for user %s (uid=%s)", user.login, user.id)

        body = (
            "<!DOCTYPE html>"
            "<html><head><meta charset='utf-8'>"
            "<title>OdooConnect</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            "</head>"
            "<body style='font-family:-apple-system,system-ui,sans-serif;"
            "padding:32px;text-align:center;color:#1d1d1f'>"
            "<h2>Erfolg</h2>"
            "<p>Du wirst zurück zur App geleitet …</p>"
            f"<script>window.location.replace({callback!r});</script>"
            "</body></html>"
        )
        return request.make_response(
            body,
            headers=[("Content-Type", "text/html; charset=utf-8")],
        )
