/// Kick a connected player by ckey, attributed to an external (Discord) admin.
/datum/world_topic/symphony/kick
	keyword = "symphony_kick"
	require_comms_key = TRUE

/datum/world_topic/symphony/kick/Run(list/input)
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
	to_chat(found, span_userdanger("You have been kicked from the server by [html_encode(admin_name)]."))
	log_admin("[admin_name] (via Symphony) kicked [key_name(found)].")
	message_admins("[html_encode(admin_name)] (via Symphony) kicked [key_name(found)].")
	qdel(found) // routes through /client/Destroy - clean disconnect
	.["success"] = TRUE

/// The roles the panel/command can ban: 'Server' (full login-enforced ban) + abstract roles + every job title.
/datum/world_topic/symphony/bannable_roles
	keyword = "symphony_bannable_roles"
	require_comms_key = TRUE
	log = FALSE

/// The canonical list of bannable roles. Shared by the topic and symphony_ban's validation so they can't drift.
/proc/symphony_bannable_roles()
	var/list/roles = list("Server", "OOC", "Deadchat", "Emote", "Appearance", "Urgent Adminhelp")
	for(var/datum/job/job_datum as anything in SSjob?.all_occupations)
		if(job_datum.title)
			roles += job_datum.title
	return roles

/// Resolve caller-supplied text to the exact stored role title. The ban cache is case-sensitive, so the casing has to match.
/proc/symphony_resolve_role(supplied)
	supplied = trim(supplied)
	if(!supplied)
		return "Server"
	for(var/role in symphony_bannable_roles())
		if(LOWER_TEXT(role) == LOWER_TEXT(supplied))
			return role
	return null

/datum/world_topic/symphony/bannable_roles/Run(list/input)
	. = list()
	.["roles"] = symphony_bannable_roles()

/// Ban a ckey. role 'Server' is a full login-enforced ban, anything else is an in-round role ban. duration_mins null/0 = permanent.
/// A world topic has no usr, so create_ban is unusable - we insert the ban row ourselves.
/datum/world_topic/symphony/ban
	keyword = "symphony_ban"
	require_comms_key = TRUE

/datum/world_topic/symphony/ban/Run(list/input)
	. = list()
	var/target_ckey = ckey(input["target_ckey"])
	var/reason = input["reason"]
	var/admin_name = input["admin_name"] || "Discord Admin"
	var/role = symphony_resolve_role(input["role"])
	var/duration = text2num(input["duration_mins"]) // minutes; null/0 => permanent
	if(!duration || duration <= 0)
		duration = null
	if(!target_ckey || !reason)
		.["success"] = FALSE
		.["message"] = "missing target_ckey or reason"
		return
	if(!role)
		.["success"] = FALSE
		.["message"] = "unknown role - use one of the roles from symphony_bannable_roles"
		return
	// applies_to_admins is 0, so a staff ban would insert a row the login check ignores. Refuse rather than report a fake success.
	if(GLOB.admin_datums[target_ckey] || GLOB.deadmins[target_ckey])
		.["success"] = FALSE
		.["message"] = "target is staff - use the in-game ban panel"
		return
	if(!SSdbcore.Connect())
		.["success"] = FALSE
		.["message"] = "no database"
		return

	// Optionally widen the ban to the target's last known IP/CID. It catches shared connections too, so the caller decides - omitted means widen.
	var/widen = TRUE
	if("match_ip_cid" in input)
		widen = text2num(input["match_ip_cid"]) ? TRUE : FALSE
	var/player_ip = null
	var/player_cid = null
	if(widen)
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
		// Fixed marker, never the caller-supplied name - otherwise anyone could stamp a real staff ckey on their bans.
		"a_ckey" = "symphony",
		"a_ip" = 0,
		"a_computerid" = "symphony",
		"who" = "",
		"adminwho" = "",
	)
	if(!SSdbcore.MassInsert(format_table_name("ban"), list(row), warn = TRUE, special_columns = special_columns))
		.["success"] = FALSE
		.["message"] = "insert failed"
		return

	// Leave a note like the in-game ban panel does, so a Discord ban shows up in the notes workflow too.
	symphony_write_ban_note(target_ckey, admin_name, role, reason)

	var/dur_txt = duration ? "for [duration] minutes" : "permanently"
	var/what = (role == "Server") ? "server-banned" : "role-banned ([role])"
	log_admin("[admin_name] (via Symphony) [what] [target_ckey] [dur_txt]. Reason: [reason]")
	// Escaped - these are free text from the panel, and message_admins renders as HTML in every admin's chat.
	var/safe_admin = html_encode(admin_name)
	var/safe_reason = html_encode(reason)
	var/safe_what = html_encode(what)
	message_admins("[safe_admin] (via Symphony) [safe_what] [target_ckey] [dur_txt]. Reason: [safe_reason]")

	var/client/found = GLOB.directory[target_ckey]
	if(found)
		build_ban_cache(found) // in-round role bans take effect without a relog
		if(role == "Server")
			to_chat(found, span_userdanger("You have been [duration ? "" : "permanently "]banned by [safe_admin].\nReason: [safe_reason]"))
			qdel(found)
		else
			to_chat(found, span_userdanger("You have been [safe_what] by [safe_admin]. Reason: [safe_reason]"))
	.["success"] = TRUE
	.["role"] = role
	.["permanent"] = isnull(duration)


/**
 * Insert a ban note for a Symphony-issued ban.
 *
 * create_message() early-returns on a null usr and a world topic has no usr, so we write the row ourselves.
 */
/proc/symphony_write_ban_note(target_ckey, admin_name, role, reason)
	if(!SSdbcore.Connect())
		return FALSE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"INSERT INTO [format_table_name("messages")] 		(type, targetckey, adminckey, text, timestamp, server_ip, server_port, round_id, secret, deleted) 		VALUES ('note', :target_ckey, :admin_ckey, :text, Now(), 0, 0, :round_id, 0, 0)",
		list(
			"target_ckey" = target_ckey,
			"admin_ckey" = "symphony",
			"text" = "Banned via Symphony by [admin_name] ([role]): [reason]",
			"round_id" = GLOB.round_id,
		),
	)
	. = query.warn_execute()
	qdel(query)
