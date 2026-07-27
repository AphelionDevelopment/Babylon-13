/// Blocks the player-facing preferences import outright. Mirrors forbid_preferences_export.
/// Off by default, as the verb is gated on the whitelist role anyway.
/datum/config_entry/flag/forbid_preferences_import
	default = FALSE

/// Seconds a player must wait between import attempts.
/datum/config_entry/number/seconds_cooldown_for_preferences_import
	default = 300
	min_val = 30

/// How many .importbac backups to keep per player before the oldest is pruned.
/datum/config_entry/number/preferences_import_backup_limit
	default = 5
	min_val = 1
