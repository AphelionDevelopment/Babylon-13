/// Read all NON-hidden game config entries so the panel can list and edit them. Optional `filter` narrows by name.
/datum/world_topic/symphony_config_get
	keyword = "symphony_config_get"
	require_comms_key = TRUE
	log = FALSE

/datum/world_topic/symphony_config_get/Run(list/input)
	. = list()
	var/filter = LOWER_TEXT(trim(input["filter"]))
	var/list/entries = list()
	for(var/entry_name in global.config.entries)
		if(filter && !findtext(entry_name, filter))
			continue
		var/datum/config_entry/entry = global.config.entries[entry_name]
		if(entry.protection & CONFIG_ENTRY_HIDDEN) // never expose comms_key / DB creds
			continue
		var/etype = "string"
		var/is_list = FALSE
		if(istype(entry, /datum/config_entry/flag))
			etype = "flag"
		else if(istype(entry, /datum/config_entry/number))
			etype = "number"
		else if(istype(entry, /datum/config_entry/number_list))
			etype = "number_list"
			is_list = TRUE
		else if(istype(entry, /datum/config_entry/str_list))
			etype = "str_list"
			is_list = TRUE
		else if(istype(entry, /datum/config_entry/keyed_list))
			etype = "keyed_list"
			is_list = TRUE
		entries += list(list(
			"name" = entry.name,
			"type" = etype,
			"value" = is_list ? null : entry.config_entry_value, // list values aren't shown/edited here
			"settable" = !is_list && !(entry.protection & CONFIG_ENTRY_LOCKED),
			"file" = entry.resident_file, // config-dir-relative source file (null = code default); SSymphony writes here
		))
	.["count"] = length(entries)
	.["entries"] = entries

/// Set a scalar config entry (flag/number/string) at runtime — hot, no restart. List entries are refused.
/datum/world_topic/symphony_config_set
	keyword = "symphony_config_set"
	require_comms_key = TRUE

/datum/world_topic/symphony_config_set/Run(list/input)
	. = list()
	var/entry_name = LOWER_TEXT(trim(input["entry"]))
	var/new_value = input["value"]
	var/admin_name = input["admin_name"] || "Discord Admin"
	if(!entry_name || isnull(new_value))
		.["success"] = FALSE
		.["message"] = "missing entry or value"
		return
	var/datum/config_entry/entry = global.config.entries[entry_name]
	if(!entry)
		.["success"] = FALSE
		.["message"] = "unknown entry"
		return
	// A world_topic is NOT an admin proccall, so LOCKED/HIDDEN are NOT auto-guarded — enforce here.
	if(entry.protection & (CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN))
		.["success"] = FALSE
		.["message"] = "protected entry"
		return
	if(istype(entry, /datum/config_entry/str_list) || istype(entry, /datum/config_entry/keyed_list) || istype(entry, /datum/config_entry/number_list))
		.["success"] = FALSE
		.["message"] = "list configs are not editable here"
		return
	var/old_value = entry.config_entry_value
	if(!entry.ValidateAndSet("[new_value]")) // writes config_entry_value in place -> CONFIG_GET is live immediately
		.["success"] = FALSE
		.["message"] = "validation failed"
		return
	entry.modified = TRUE
	log_admin("[admin_name] (via Symphony) set config [entry.name] = [new_value] (was [old_value])")
	message_admins("[admin_name] (via Symphony) changed config [entry.name] to [entry.config_entry_value].")
	.["success"] = TRUE
	.["name"] = entry.name
	.["value"] = entry.config_entry_value
