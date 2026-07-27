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

/// TRUE if the gate is off, or the ckey holds the in-game "whitelist" role.
/proc/is_symphony_whitelisted(target_ckey)
	if(!CONFIG_GET(flag/symphony_enabled))
		return TRUE
	return symphony_has_ingame_role(target_ckey, "whitelist")
