/**
 * Discord role to in-game admin rank.
 *
 * Reuses the generic `ingame` grant mechanism: a Discord role is mapped to the in-game role key
 * `admin:<rank name>`, and anyone holding that Discord role (and having linked their ckey) is built as
 * an admin of that rank on every admin reload.
 *
 * Keys are generated from the game's own loaded ranks rather than declared by hand, so the panel can
 * never offer a rank that does not exist. ranks_from_rank_name() returns an empty list for an unknown
 * name and the caller silently gets no admin, which is a miserable failure mode to debug.
 *
 * Off by default. The whole feature is gated behind the symphony_discord_admin_sync config flag,
 * because it lets anyone who can assign a Discord role mint game admins.
 */

/// Prefix marking an in-game role key as "this is an admin rank". Everything after it is the rank name.
#define SYMPHONY_ADMIN_ROLE_PREFIX "admin:"

/// TRUE when Discord-role-driven admin granting is enabled.
/proc/symphony_discord_admin_sync_enabled()
	return CONFIG_GET(flag/symphony_discord_admin_sync)

/**
 * Applies Discord-granted admin ranks. Called at the end of load_admins(), which Cut()s GLOB.admin_datums,
 * so this has to run as part of that flow rather than alongside it or a reload would silently drop them.
 *
 * One database query per rank, not per player: symphony_ingame_role_ckeys() returns every holder at once.
 * That matters because load_admins() runs on a reload with everyone connected.
 *
 * Never overwrites an existing admin. Someone already loaded from admins.txt or the admin table keeps the
 * rank they were given there, so a Discord role cannot silently downgrade (or upgrade) a real admin entry.
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
		// Fail-closed: null means the query failed, which is different from "nobody holds it". Granting
		// nothing is the safe direction; the next reload retries.
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
 * Runs after the ranks are loaded, since GLOB.admin_ranks is empty until then. Only populated while the
 * feature is enabled, so with the toggle off the panel does not offer admin ranks at all.
 */
/proc/symphony_refresh_admin_role_keys()
	// Drop any previously generated keys so a renamed or removed rank does not linger in the panel.
	for(var/key in GLOB.symphony_ingame_roles)
		if(findtext(key, SYMPHONY_ADMIN_ROLE_PREFIX) == 1)
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
 * Separate from symphony_ingame_roles on purpose. That list only carries `admin:` keys while Discord
 * sync is enabled, but granting a rank from the panel is independent of that toggle and has to work
 * with it off.
 */
/datum/world_topic/symphony_admin_ranks
	keyword = "symphony_admin_ranks"
	require_comms_key = TRUE

/datum/world_topic/symphony_admin_ranks/Run(list/input)
	. = list()
	var/list/ranks = list()
	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(!rank?.name)
			continue
		ranks += list(list(
			"name" = rank.name,
			// Ranks sourced from admins.txt cannot be reassigned by editing the admin table, so the panel
			// greys them out rather than offering a grant that silently does nothing.
			"protected" = (rank.name in GLOB.protected_ranks) ? TRUE : FALSE,
		))
	.["ranks"] = ranks
	.["discord_sync"] = symphony_discord_admin_sync_enabled() ? TRUE : FALSE

/**
 * Reloads admins, so a rank granted from the panel takes effect without waiting for a round restart.
 *
 * The panel writes the row to the `admin` table itself and calls this afterwards, so this is advisory:
 * if the game is offline the grant is already persisted and gets picked up by the next reload. That is
 * why the panel treats a failure here as "delayed", not "failed".
 */
/datum/world_topic/symphony_reload_admins
	keyword = "symphony_reload_admins"
	require_comms_key = TRUE

/datum/world_topic/symphony_reload_admins/Run(list/input)
	. = list()
	load_admins()
	.["success"] = TRUE
	.["admins"] = length(GLOB.admin_datums)
	log_admin("Symphony: admins reloaded from the panel.")

#undef SYMPHONY_ADMIN_ROLE_PREFIX
