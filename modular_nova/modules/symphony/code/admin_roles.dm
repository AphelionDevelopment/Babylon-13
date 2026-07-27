/**
 * Discord role to in-game admin rank.
 *
 * A Discord role maps to the in-game role key `admin:<rank name>`, and its holders are built as admins of that rank on every admin reload.
 * Keys are generated from the game's own loaded ranks, so the panel can never offer a rank that does not exist.
 */

/// Prefix marking an in-game role key as an admin rank - everything after it is the rank name.
#define SYMPHONY_ADMIN_ROLE_PREFIX "admin:"

/// TRUE when Discord-role-driven admin granting is enabled.
/proc/symphony_discord_admin_sync_enabled()
	return CONFIG_GET(flag/symphony_discord_admin_sync)

/**
 * Applies Discord-granted admin ranks.
 *
 * Has to run at the end of load_admins(), which Cut()s GLOB.admin_datums - run it alongside and a reload drops them.
 * Never overwrites an existing admin, so a Discord role cannot upgrade or downgrade a real admin entry.
 */
/proc/symphony_apply_discord_admins()
	if(!symphony_discord_admin_sync_enabled())
		return 0

	var/granted = 0
	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(!rank?.name)
			continue
		var/role_key = "[SYMPHONY_ADMIN_ROLE_PREFIX][rank.name]"
		var/list/holders = symphony_ingame_role_ckeys(role_key)
		// Fail closed - null means the query failed, not "nobody holds it". Grant nothing and let the next reload retry.
		if(isnull(holders))
			continue
		for(var/holder_ckey in holders)
			if(GLOB.admin_datums[holder_ckey] || GLOB.deadmins[holder_ckey])
				continue
			var/list/ranks = ranks_from_rank_name(rank.name)
			if(!length(ranks))
				continue
			new /datum/admins(ranks, holder_ckey)
			granted++

	if(granted)
		log_admin("Symphony: granted [granted] admin\s from Discord roles.")
	return granted

/**
 * Adds one in-game role key per admin rank to the list the panel can map Discord roles to.
 *
 * Runs after the ranks are loaded, since GLOB.admin_ranks is empty until then.
 */
/proc/symphony_refresh_admin_role_keys()
	// Drop any previously generated keys so a renamed or removed rank does not linger in the panel.
	// Collected first, removed after - deleting inside the loop would skip every other match.
	var/list/stale = list()
	for(var/key in GLOB.symphony_ingame_roles)
		if(findtext(key, SYMPHONY_ADMIN_ROLE_PREFIX) == 1)
			stale += key
	for(var/key in stale)
		GLOB.symphony_ingame_roles -= key

	if(!symphony_discord_admin_sync_enabled())
		return

	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(!rank?.name)
			continue
		GLOB.symphony_ingame_roles["[SYMPHONY_ADMIN_ROLE_PREFIX][rank.name]"] = "Grants the in-game admin rank \"[rank.name]\"."

/**
 * The admin ranks this server has loaded, so the panel can offer them when granting a rank directly.
 *
 * Separate from symphony_ingame_roles, which only carries `admin:` keys while Discord sync is on - this has to work with it off.
 */
/datum/world_topic/symphony/admin_ranks
	keyword = "symphony_admin_ranks"
	require_comms_key = TRUE

/datum/world_topic/symphony/admin_ranks/Run(list/input)
	. = list()
	var/list/ranks = list()
	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(!rank?.name)
			continue
		ranks += list(list(
			"name" = rank.name,
			// admins.txt ranks cannot be reassigned by editing the admin table, so the panel greys them out.
			// protected_ranks holds the rank datums themselves, not their names - testing the name here was always FALSE.
			"protected" = (rank in GLOB.protected_ranks) ? TRUE : FALSE,
		))
	.["ranks"] = ranks
	.["discord_sync"] = symphony_discord_admin_sync_enabled() ? TRUE : FALSE
	// With the legacy system on, load_admins() never reads the SQL admin tables, so a grant from the panel writes a row nothing loads.
	.["legacy_admin_system"] = CONFIG_GET(flag/admin_legacy_system) ? TRUE : FALSE

/**
 * Reloads admins, so a rank granted from the panel takes effect without waiting for a round restart.
 *
 * Advisory only - the panel has already written the row, so a failure here just means the next reload picks it up.
 */
/datum/world_topic/symphony/reload_admins
	keyword = "symphony_reload_admins"
	require_comms_key = TRUE

/datum/world_topic/symphony/reload_admins/Run(list/input)
	. = list()
	load_admins()
	.["success"] = TRUE
	.["admins"] = length(GLOB.admin_datums)
	log_admin("Symphony: admins reloaded from the panel.")

#undef SYMPHONY_ADMIN_ROLE_PREFIX
