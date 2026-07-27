/// TRUE if the ckey's linked Discord holds any role that grants the given in-game role key.
/// Reads the SSymphony grants table (grant_type='ingame'); modular - 'whitelist' now, 'staff'/'donator' later.
/// Fail-closed: any error (no DB, query failure) returns FALSE.
/proc/symphony_has_ingame_role(target_ckey, role_key)
	target_ckey = ckey(target_ckey)
	if(!target_ckey || !role_key)
		return FALSE
	if(!SSdbcore.Connect())
		return FALSE

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT 1 FROM [format_table_name("discord_links")] AS dl \
		JOIN [format_table_name("discord_member_roles")] AS mr ON mr.discord_id = dl.discord_id \
		JOIN [format_table_name("symphony_role_grants")] AS g ON g.discord_role_id = mr.role_id \
		WHERE dl.ckey = :ckey AND dl.valid = 1 AND g.grant_type = 'ingame' AND g.grant_key = :role_key LIMIT 1",
		list("ckey" = target_ckey, "role_key" = role_key),
	)
	if(!query.warn_execute())
		qdel(query)
		return FALSE
	. = query.NextRow()
	qdel(query)

/// Every ckey that currently holds the given in-game role key, as an assoc set (ckey -> TRUE).
/// One query for the whole server, so callers building a player list don't run a query per player.
/// Fail-closed: returns null (not an empty list) on any DB error, so callers can tell "nobody holds it"
/// apart from "couldn't check" and stay consistent with the single-ckey path.
/proc/symphony_ingame_role_ckeys(role_key)
	if(!role_key || !SSdbcore.Connect())
		return null

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT DISTINCT dl.ckey FROM [format_table_name("discord_links")] AS dl \
		JOIN [format_table_name("discord_member_roles")] AS mr ON mr.discord_id = dl.discord_id \
		JOIN [format_table_name("symphony_role_grants")] AS g ON g.discord_role_id = mr.role_id \
		WHERE dl.valid = 1 AND g.grant_type = 'ingame' AND g.grant_key = :role_key",
		list("role_key" = role_key),
	)
	if(!query.warn_execute())
		qdel(query)
		return null
	var/list/holders = list()
	while(query.NextRow())
		holders[ckey(query.item[1])] = TRUE
	qdel(query)
	return holders

/**
 * Short-lived cache of whitelist answers, keyed by ckey.
 *
 * The lookup is a three-table JOIN and had no cache, so it ran per call for whitelisted players too.
 * Fine for one click, bad on the paths that fan out: show_title_screen() renders for EVERY lobby mob and
 * is called on each dynamic ruleset queue and again from create_characters() at round start, so a
 * 50-strong lobby cost 50 queries at the most timing-sensitive tick of the round.
 *
 * Deliberately brief, and dropped outright on every grant, revoke and sweep. Those pushes are the
 * authority; this only collapses bursts within a single render.
 */
GLOBAL_LIST_EMPTY(symphony_whitelist_cache)
/// world.time at which each cached answer stops being trusted.
GLOBAL_LIST_EMPTY(symphony_whitelist_cache_expiry)

/// How long a cached whitelist answer is reused for.
#define SYMPHONY_WHITELIST_CACHE_TIME (10 SECONDS)

/// Drop a ckey's cached answer, so a grant or revoke is visible immediately rather than after the TTL.
/proc/symphony_invalidate_whitelist_cache(target_ckey)
	target_ckey = ckey(target_ckey)
	if(!target_ckey)
		return
	GLOB.symphony_whitelist_cache -= target_ckey
	GLOB.symphony_whitelist_cache_expiry -= target_ckey

/**
 * TRUE if the gate is off, or the ckey holds the in-game "whitelist" role.
 *
 * Fail-OPEN when the module is disabled, which is right for a GATE (do not lock a server out of its own
 * lobby) and wrong for an ENTITLEMENT. Callers deciding "may this player use a restricted feature"
 * must use symphony_holds_whitelist_role() instead, or the feature unlocks for everyone precisely when
 * Symphony is switched off.
 */
/proc/is_symphony_whitelisted(target_ckey)
	if(!CONFIG_GET(flag/symphony_enabled))
		return TRUE
	target_ckey = ckey(target_ckey)
	if(!target_ckey)
		return FALSE
	var/expiry = GLOB.symphony_whitelist_cache_expiry[target_ckey]
	if(expiry && world.time < expiry)
		return GLOB.symphony_whitelist_cache[target_ckey]
	. = symphony_has_ingame_role(target_ckey, "whitelist")
	GLOB.symphony_whitelist_cache[target_ckey] = .
	GLOB.symphony_whitelist_cache_expiry[target_ckey] = world.time + SYMPHONY_WHITELIST_CACHE_TIME

/**
 * TRUE only when the ckey actually holds the whitelist role. Fail-CLOSED: a disabled module means nobody
 * holds it, because nothing has granted it.
 *
 * This is the entitlement form. The preferences importer used the gate form, so on a stock server (where
 * symphony_enabled defaults off) every connecting player was handed the verb AND advertised it by the
 * one-time notice, which is the exact inverse of what the module documents.
 */
/proc/symphony_holds_whitelist_role(target_ckey)
	if(!CONFIG_GET(flag/symphony_enabled))
		return FALSE
	return symphony_has_ingame_role(target_ckey, "whitelist")

#undef SYMPHONY_WHITELIST_CACHE_TIME
