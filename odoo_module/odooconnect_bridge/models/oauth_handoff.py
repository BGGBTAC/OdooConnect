import hashlib
from datetime import timedelta

from odoo import api, fields, models


class OdooConnectOAuthHandoff(models.Model):
    """Single-use, server-only store for an OAuth handoff secret.

    Replaces the previous ``ir.config_parameter`` storage, which kept the
    plaintext API key in a table readable by every Settings admin and in
    every DB backup. Here:

    * the lookup key is stored as a SHA-256 hash of the one-time code, so a
      DB/backup leak does not reveal the redemption code;
    * the record has NO ACL grant to any group (see security/), so it is
      reachable only via ``sudo()`` from the controller;
    * an ir.cron sweeps expired rows, instead of relying on lazy cleanup.

    The api_key is still stored in cleartext for the short TTL because the
    app must receive it once over HTTPS — but only in this restricted model.
    """

    _name = "odooconnect.oauth.handoff"
    _description = "OdooConnect one-time OAuth handoff (server-only secrets)"
    _rec_name = "code_hash"

    code_hash = fields.Char(required=True, index=True)
    api_key = fields.Char(required=True)
    uid = fields.Integer(required=True)
    login = fields.Char(required=True)
    database = fields.Char(required=True)
    expires_at = fields.Datetime(required=True, index=True)

    @staticmethod
    def _hash(code):
        return hashlib.sha256((code or "").encode("utf-8")).hexdigest()

    @api.model
    def stash(self, code, api_key, uid, login, database, ttl):
        """Persist a handoff keyed by sha256(code), expiring after ``ttl`` s."""
        self.sudo().create({
            "code_hash": self._hash(code),
            "api_key": api_key,
            "uid": uid,
            "login": login,
            "database": database,
            "expires_at": fields.Datetime.now() + timedelta(seconds=ttl),
        })

    @api.model
    def redeem(self, code):
        """Return the stored payload for ``code`` exactly once, else None.

        The matching record is unlinked on any redeem attempt (success or
        expiry), enforcing single-use.
        """
        rec = self.sudo().search([("code_hash", "=", self._hash(code))], limit=1)
        if not rec:
            return None
        valid = bool(rec.expires_at) and rec.expires_at >= fields.Datetime.now()
        data = None
        if valid:
            data = {
                "api_key": rec.api_key,
                "uid": rec.uid,
                "login": rec.login,
                "database": rec.database,
            }
        rec.sudo().unlink()
        return data

    @api.model
    def _gc_expired(self):
        """Cron entry point: drop rows whose TTL has elapsed."""
        self.sudo().search([("expires_at", "<", fields.Datetime.now())]).unlink()
