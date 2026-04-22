{
    "name": "OdooConnect Bridge",
    "version": "1.0.0",
    "summary": "API-key minting endpoint for the OdooConnect iOS app",
    "description": """
        Companion module for the OdooConnect iOS client.

        Adds a single endpoint at /api/odooconnect/oauth_complete that runs
        after a user signs in to Odoo (via password OR any configured OAuth
        provider — Google, Microsoft, etc.) and bounces them back into the
        iOS app via a custom URL scheme, carrying a freshly minted API key.

        The iOS app stores the key in Keychain and uses it for all subsequent
        JSON-RPC calls.  Sessions are not relied on after the bounce.
    """,
    "author": "Benedict",
    "category": "Tools",
    "license": "LGPL-3",
    "depends": ["base", "web"],
    "data": [],
    "installable": True,
    "application": False,
}
