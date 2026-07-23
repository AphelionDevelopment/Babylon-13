/// Master switch. Off by default — the whole module is inert until an operator enables it.
/datum/config_entry/flag/symphony_enabled

/// Base URL of the SSymphony service, e.g. https://symphony.example.com
/datum/config_entry/string/symphony_url

/// Grace period, in seconds, between losing the role and being returned to the lobby.
/datum/config_entry/number/symphony_grace_seconds
	default = 30
	integer = TRUE
	min_val = 0
