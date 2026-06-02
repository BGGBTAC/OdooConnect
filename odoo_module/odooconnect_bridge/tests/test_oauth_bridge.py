from datetime import timedelta

from odoo import fields
from odoo.exceptions import AccessError
from odoo.tests.common import TransactionCase, new_test_user


class TestOAuthHandoff(TransactionCase):
    def setUp(self):
        super().setUp()
        self.Handoff = self.env["odooconnect.oauth.handoff"]

    def _stash(self, code="abc", ttl=120):
        self.Handoff.stash(
            code=code,
            api_key="KEY-123",
            uid=self.env.user.id,
            login=self.env.user.login,
            database=self.env.cr.dbname,
            ttl=ttl,
        )

    def test_stash_stores_hash_not_raw_code(self):
        self._stash(code="secret-code")
        rec = self.Handoff.sudo().search([], limit=1)
        self.assertTrue(rec)
        self.assertNotEqual(rec.code_hash, "secret-code")
        self.assertEqual(rec.code_hash, self.Handoff._hash("secret-code"))
        self.assertEqual(len(rec.code_hash), 64)  # sha256 hex digest

    def test_redeem_returns_key_and_consumes(self):
        self._stash(code="c1")
        data = self.Handoff.redeem(code="c1")
        self.assertEqual(data["api_key"], "KEY-123")
        self.assertEqual(data["login"], self.env.user.login)
        # Single-use: a second redemption finds nothing.
        self.assertIsNone(self.Handoff.redeem(code="c1"))

    def test_redeem_unknown_code(self):
        self.assertIsNone(self.Handoff.redeem(code="does-not-exist"))

    def test_redeem_expired_is_rejected_and_consumed(self):
        self._stash(code="old", ttl=120)
        rec = self.Handoff.sudo().search([], limit=1)
        rec.expires_at = fields.Datetime.now() - timedelta(seconds=10)
        self.assertIsNone(self.Handoff.redeem(code="old"))
        # Consumed even on expiry, so a leaked code can't linger.
        self.assertFalse(self.Handoff.sudo().search([]))

    def test_gc_expired_unlinks_only_expired(self):
        self._stash(code="fresh", ttl=600)
        self._stash(code="stale", ttl=600)
        stale = self.Handoff.sudo().search([], limit=1, order="id desc")
        stale.expires_at = fields.Datetime.now() - timedelta(seconds=10)
        self.Handoff._gc_expired()
        remaining = self.Handoff.sudo().search([])
        self.assertEqual(len(remaining), 1)

    def test_no_acl_access_for_normal_user(self):
        # The model has no ACL grant to any group, so non-sudo access raises.
        user = new_test_user(self.env, login="oc_bridge_test_user")
        self._stash(code="x")
        with self.assertRaises(AccessError):
            self.env["odooconnect.oauth.handoff"].with_user(user).search([])
