/// Master switch. Off by default, the whole module is inert until an operator enables it.
/datum/config_entry/flag/symphony_enabled

/// Base URL of the SSymphony service, e.g. https://symphony.example.com
/datum/config_entry/string/symphony_url

/// Grace period, in seconds, between losing the role and being returned to the lobby.
/// Capped below SSsymphony's 5-minute sweep: a longer grace than the re-check interval means each sweep
/// re-arms the timer before the previous one fires, so enforcement never actually happens.
/datum/config_entry/number/symphony_grace_seconds
	default = 30
	integer = TRUE
	min_val = 0
	max_val = 240

/// Lets Discord roles confer in-game admin ranks, via the `admin:<rank>` in-game role keys.
/// OFF by default and deliberately so: with it on, anyone who can assign the mapped Discord role can
/// mint game admins. Turning it off stops Discord from granting admin; it does not touch admins granted
/// from admins.txt, the admin table, or the panel.
/datum/config_entry/flag/symphony_discord_admin_sync
	default = FALSE
