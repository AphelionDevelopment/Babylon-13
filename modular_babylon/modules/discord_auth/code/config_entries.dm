/// Master switch. Off by default — the whole module is inert until an operator enables it.
/datum/config_entry/flag/discord_auth_enabled

/// Base URL of the SSymphony service, e.g. https://symphony.example.com
/datum/config_entry/string/discord_auth_symphony_url

/// Discord role id that grants whitelist access.
/datum/config_entry/string/discord_auth_whitelist_role_id

/// Grace period, in seconds, between losing the role and being returned to the lobby.
/datum/config_entry/number/discord_auth_grace_seconds
	default = 30
	integer = TRUE
	min_val = 0
