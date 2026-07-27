/// Master switch. Off by default, the whole module is inert until an operator enables it.
/datum/config_entry/flag/symphony_enabled

/// Base URL of the SSymphony service, e.g. https://symphony.example.com
/datum/config_entry/string/symphony_url

/// Grace period, in seconds, between losing the role and being returned to the lobby.
/// Kept under SSsymphony's 5 minute sweep, or every sweep re-arms the timer and enforcement never fires.
/datum/config_entry/number/symphony_grace_seconds
	default = 30
	integer = TRUE
	min_val = 0
	max_val = 240

/// Lets Discord roles confer in-game admin ranks, via the `admin:<rank>` in-game role keys.
/// Off by default on purpose - with it on, anyone who can assign the mapped Discord role can mint game admins.
/datum/config_entry/flag/symphony_discord_admin_sync
	default = FALSE

/// Refuses Symphony world topics that do not come from an allowed address, so a leaked comms key is not enough on its own.
/// Off by default - turn it on once you know where the panel talks to the game from.
/datum/config_entry/flag/symphony_topics_local_only
	default = FALSE

/// Addresses the gate lets through on top of the local ones, one entry per line, for a panel that does not share a machine with the game.
/// Loopback and same-machine senders are always allowed, so a single-box deployment leaves this empty.
/datum/config_entry/str_list/symphony_topics_allowed_addresses
