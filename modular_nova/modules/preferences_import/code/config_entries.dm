/// Blocks the player-facing preferences import outright. Mirrors forbid_preferences_export.
/// Off by default: the verb is additionally gated on the player holding the in-game whitelist role, so
/// it is unreachable on a server that has not enabled the Symphony whitelist at all.
/datum/config_entry/flag/forbid_preferences_import
	default = FALSE

/// Seconds a player must wait between import attempts. Imports replace a savefile and kick the player,
/// so this is about limiting self-inflicted churn and disk turnover rather than abuse of others.
/datum/config_entry/number/seconds_cooldown_for_preferences_import
	default = 300
	min_val = 30

/// How many .importbac backups to keep per player before the oldest is pruned. The admin verb refuses
/// the import once its limit is hit, which for a self-service flow would be a permanent self-lockout;
/// this one prunes instead.
/datum/config_entry/number/preferences_import_backup_limit
	default = 5
	min_val = 1
