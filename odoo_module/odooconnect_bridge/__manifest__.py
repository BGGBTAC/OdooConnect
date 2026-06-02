{
    "name": "OdooConnect Bridge",
    "version": "19.0.1.1.0",
    "summary": "API-key minting endpoint for the OdooConnect iOS app",
    "description": """
        Companion module for the OdooConnect iOS client.

        Adds endpoints under /api/odooconnect/ that run after a user signs in
        to Odoo (via password OR any configured OAuth provider — Google,
        Microsoft, etc.) and bounce them back into the iOS app via a custom
        URL scheme, carrying a freshly minted API key.

        Security model:
        * Key minting happens on a CSRF-protected POST (/oauth_mint), reached
          only from the same-origin form served by /oauth_complete. The bare
          GET has no side effect, so it cannot be CSRF-forged into minting.
        * The one-time handoff secret is held in a sudo-only model keyed by a
          SHA-256 hash of the code (not in ir.config_parameter), and is swept
          by an ir.cron.

        The iOS app stores the key in Keychain and uses it for all subsequent
        JSON-RPC calls.  Sessions are not relied on after the bounce.
    """,
    "author": "Benedict",
    "category": "Tools",
    "license": "LGPL-3",
    "depends": ["base", "web"],
    "data": [
        "security/ir.model.access.csv",
        "data/ir_cron.xml",
    ],
    "installable": True,
    "application": False,
}
