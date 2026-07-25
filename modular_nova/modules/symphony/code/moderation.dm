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

/// The roles the panel/command can ban: 'Server' (full login-enforced ban) + abstract roles + every job title.
/datum/world_topic/symphony_bannable_roles
	keyword = "symphony_bannable_roles"
	require_comms_key = TRUE
	log = FALSE

/datum/world_topic/symphony_bannable_roles/Run(list/input)
	. = list()
	var/list/roles = list("Server", "OOC", "Deadchat", "Emote", "Appearance", "Urgent Adminhelp")
	for(var/datum/job/job_datum as anything in SSjob?.all_occupations)
		if(job_datum.title)
			roles += job_datum.title
	.["roles"] = roles

/// Ban a ckey. role='Server' = permanent/temp full server ban (login-enforced + kick); any other role =
/// in-round role/job ban. duration_mins null/0 = permanent, else a temporary ban of that many minutes.
/// A world_topic has no usr, so create_ban is unusable — insert the ban row directly.
/datum/world_topic/symphony_ban
	keyword = "symphony_ban"
	require_comms_key = TRUE

/datum/world_topic/symphony_ban/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	var/reason = input["reason"]
	var/admin_name = input["admin_name"] || "Discord Admin"
	var/role = trim(input["role"])
	if(!role)
		role = "Server"
	role = copytext(role, 1, 33) // ban.role is VARCHAR(32)
	var/duration = text2num(input["duration_mins"]) // minutes; null/0 => permanent
	if(!duration || duration <= 0)
		duration = null
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
		"expiration_time" = "IF(? IS NULL, NULL, NOW() + INTERVAL ? MINUTE)", // one row value fills both '?'
	)
	var/list/row = list(
		"server_ip" = 0,
		"server_port" = world.port,
		"round_id" = GLOB.round_id,
		"role" = role, // 'Server' = full login-enforced ban; anything else = in-round role ban
		"expiration_time" = duration, // null = permanent, else minutes
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

	var/dur_txt = duration ? "for [duration] minutes" : "permanently"
	var/what = (role == "Server") ? "server-banned" : "role-banned ([role])"
	log_admin("[admin_name] (via Symphony) [what] [target_ckey] [dur_txt]. Reason: [reason]")
	message_admins("[admin_name] (via Symphony) [what] [target_ckey] [dur_txt]. Reason: [reason]")

	var/client/found = GLOB.directory[target_ckey]
	if(found)
		build_ban_cache(found) // in-round role bans take effect without a relog
		if(role == "Server")
			to_chat(found, span_userdanger("You have been [duration ? "" : "permanently "]banned by [admin_name].\nReason: [reason]"))
			qdel(found)
		else
			to_chat(found, span_userdanger("You have been [what] by [admin_name]. Reason: [reason]"))
	.["success"] = TRUE
	.["role"] = role
	.["permanent"] = isnull(duration)
