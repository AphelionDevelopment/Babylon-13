/// TRUE if the ckey's linked Discord holds any role that grants the given in-game role key.
/// Reads the SSymphony grants table (grant_type='ingame'). Fail-closed - any DB error returns FALSE.
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
/// One query for the whole server, so building a player list doesn't cost a query per player.
/// Fail-closed - returns null, not an empty list, so callers can tell "nobody holds it" from "couldn't check".
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

/// Short-lived cache of whitelist answers, keyed by ckey. Only collapses bursts - grants, revokes and sweeps drop it outright.
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
 * Fail-OPEN when disabled - right for a GATE, wrong for an ENTITLEMENT. "May this player use a restricted feature" wants symphony_holds_whitelist_role().
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

/// The entitlement form - TRUE only when the ckey actually holds the whitelist role.
/// Fail-CLOSED: a disabled module means nobody holds it, because nothing has granted it.
/proc/symphony_holds_whitelist_role(target_ckey)
	if(!CONFIG_GET(flag/symphony_enabled))
		return FALSE
	return symphony_has_ingame_role(target_ckey, "whitelist")

#undef SYMPHONY_WHITELIST_CACHE_TIME
