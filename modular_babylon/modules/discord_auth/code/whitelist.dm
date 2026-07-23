/// TRUE if the gate is off, or the ckey is linked to a Discord account that currently holds the whitelist role.
/// Fail-closed: any error (no DB, no role configured, query failure) returns FALSE when the gate is enabled.
/proc/is_discord_whitelisted(target_ckey)
	if(!CONFIG_GET(flag/discord_auth_enabled))
		return TRUE
	target_ckey = ckey(target_ckey)
	if(!target_ckey)
		return FALSE
	var/role_id = CONFIG_GET(string/discord_auth_whitelist_role_id)
	if(!role_id)
		return FALSE
	if(!SSdbcore.Connect())
		return FALSE

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT 1 FROM [format_table_name("discord_links")] AS dl \
		JOIN [format_table_name("discord_member_roles")] AS r ON r.discord_id = dl.discord_id \
		WHERE dl.ckey = :ckey AND dl.valid = 1 AND r.role_id = :role LIMIT 1",
		list("ckey" = target_ckey, "role" = role_id),
	)
	if(!query.warn_execute())
		qdel(query)
		return FALSE
	. = query.NextRow()
	qdel(query)
