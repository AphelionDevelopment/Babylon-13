# discord_auth

Discord-role whitelist gate for the server, paired with the **SSymphony** bridge (separate repo). Players must link their Discord and hold a configured role to enter a round, and are returned to the lobby (after a grace period) if they lose it.

**Off by default** — with `DISCORD_AUTH_ENABLED` unset the module is completely inert and the server behaves normally.

## How it works

- Un-whitelisted players can't ready up or late-join (`is_ready_to_play` / `AttemptLateSpawn` are gated, fail-closed). They use the **Get Whitelisted** verb (OOC tab), which opens SSymphony's OAuth flow using a one-time `discord_links` token.
- The whitelist check reads the shared MySQL: a ckey is whitelisted iff its linked `discord_id` holds the configured role in `discord_member_roles` (kept current by SSymphony).
- SSymphony pushes `whitelist_revoke` / `whitelist_grant` world topics; on revoke, the player gets a grace period then is returned to the lobby. `SSdiscord_auth` re-checks connected players periodically as a safety net.

## Config (add to your config to enable)

| Key | Meaning |
|-----|---------|
| `DISCORD_AUTH_ENABLED` | Master switch (flag). |
| `DISCORD_AUTH_SYMPHONY_URL` | SSymphony base URL, e.g. `https://symphony.example.com`. |
| `DISCORD_AUTH_WHITELIST_ROLE_ID` | Discord role id required to play. |
| `DISCORD_AUTH_GRACE_SECONDS` | Seconds between losing the role and lobby return (default 30). |

Requires the SQL backend enabled and SSymphony running against the **same** database, with matching table prefix. See the SSymphony repo for the bridge setup.
