/// Kick a connected player by ckey, attributed to an external (Discord) admin.
/datum/world_topic/symphony_kick
	keyword = "symphony_kick"
	require_comms_key = TRUE

/datum/world_topic/symphony_kick/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	var/admin_name = input["admin_name"] || "Discord Admin"
	if(!target_ckey)
		.["success"] = FALSE
		.["message"] = "missing target_ckey"
		return
	var/client/found = GLOB.directory[target_ckey]
	if(!found)
		.["success"] = FALSE
		.["message"] = "not connected"
		return
	to_chat(found, span_userdanger("You have been kicked from the server by [admin_name]."))
	log_admin("[admin_name] (via Symphony) kicked [key_name(found)].")
	message_admins("[admin_name] (via Symphony) kicked [key_name(found)].")
	qdel(found) // routes through /client/Destroy — clean disconnect
	.["success"] = TRUE

/// Permanent full server ban by ckey, attributed to an external admin. Works even if the target is offline.
/// A world_topic has no usr, so the built-in create_ban is unusable — insert the ban row directly.
/datum/world_topic/symphony_ban
	keyword = "symphony_ban"
	require_comms_key = TRUE

/datum/world_topic/symphony_ban/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	var/reason = input["reason"]
	var/admin_name = input["admin_name"] || "Discord Admin"
	if(!target_ckey || !reason)
		.["success"] = FALSE
		.["message"] = "missing target_ckey or reason"
		return
	if(!SSdbcore.Connect())
		.["success"] = FALSE
		.["message"] = "no database"
		return

	// Widen the ban to the target's last-known IP/CID so it isn't trivially evaded.
	var/player_ip = null
	var/player_cid = null
	var/datum/db_query/lookup = SSdbcore.NewQuery(
		"SELECT INET_NTOA(ip), computerid FROM [format_table_name("player")] WHERE ckey = :ckey",
		list("ckey" = target_ckey),
	)
	if(lookup.warn_execute() && lookup.NextRow())
		player_ip = lookup.item[1]
		player_cid = lookup.item[2]
	qdel(lookup)

	var/list/special_columns = list(
		"bantime" = "NOW()",
		"ip" = "INET_ATON(?)", // INET_ATON(null) -> null, fine (ip is nullable)
	)
	var/list/row = list(
		"server_ip" = 0,
		"server_port" = world.port,
		"round_id" = GLOB.round_id,
		"role" = "Server", // full server ban — enforced at login
		"expiration_time" = null, // null == permanent
		"applies_to_admins" = 0,
		"reason" = reason,
		"ckey" = target_ckey,
		"ip" = player_ip,
		"computerid" = player_cid,
		"a_ckey" = ckey(admin_name) || "symphony",
		"a_ip" = 0,
		"a_computerid" = "symphony",
		"who" = "",
		"adminwho" = "",
	)
	if(!SSdbcore.MassInsert(format_table_name("ban"), list(row), warn = TRUE, special_columns = special_columns))
		.["success"] = FALSE
		.["message"] = "insert failed"
		return

	log_admin("[admin_name] (via Symphony) permanently server-banned [target_ckey]. Reason: [reason]")
	message_admins("[admin_name] (via Symphony) permanently server-banned [target_ckey]. Reason: [reason]")

	// The insert alone does not disconnect — kick them if they're online.
	var/client/found = GLOB.directory[target_ckey]
	if(found)
		build_ban_cache(found)
		to_chat(found, span_userdanger("You have been permanently banned by [admin_name].\nReason: [reason]"))
		qdel(found)
	.["success"] = TRUE
