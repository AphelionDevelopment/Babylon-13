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
		if(istype(entry, /datum/config_entry/flag))
			etype = "flag"
		else if(istype(entry, /datum/config_entry/number))
			etype = "number"
		else if(istype(entry, /datum/config_entry/number_list))
			etype = "number_list"
		else if(istype(entry, /datum/config_entry/str_list))
			etype = "str_list"
		else if(istype(entry, /datum/config_entry/keyed_list))
			etype = "keyed_list"
		entries += list(list(
			"name" = entry.name,
			"type" = etype,
			"value" = entry.config_entry_value, // actual value; lists come back as arrays / assoc objects
			"locked" = !!(entry.protection & CONFIG_ENTRY_LOCKED), // locked = editable via file (persists), no live hot-reload
			"file" = entry.resident_file, // config-dir-relative source file (null = code default); SSymphony writes here
		))
	.["count"] = length(entries)
	.["entries"] = entries

/// Set a config entry at runtime (hot, no restart). Lists are replaced (set_default + re-add each line). Hidden/locked refused (locked persists via file).
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
	// A world_topic is NOT an admin proccall, so protection is NOT auto-guarded — enforce here.
	// HIDDEN must never be touched. LOCKED can't be changed live (the SSymphony file write persists it for next boot).
	if(entry.protection & CONFIG_ENTRY_HIDDEN)
		.["success"] = FALSE
		.["message"] = "hidden entry"
		return
	if(entry.protection & CONFIG_ENTRY_LOCKED)
		.["success"] = FALSE
		.["message"] = "locked — change persisted to file, applies on restart"
		return
	var/old_value = entry.config_entry_value
	var/ok = FALSE
	if(istype(entry, /datum/config_entry/number_list))
		// number_list REPLACES the whole value on each call — pass everything as one space-separated line.
		ok = entry.ValidateAndSet(replacetext(trim(new_value), "\n", " "))
	else if(istype(entry, /datum/config_entry/str_list) || istype(entry, /datum/config_entry/keyed_list))
		// str_list appends / keyed_list assigns per key. Empty the list first (NOT set_default, which re-seeds
		// the CODE default), then add each line, so the whole list is truly REPLACED.
		var/keyed = istype(entry, /datum/config_entry/keyed_list)
		entry.config_entry_value = list()
		ok = TRUE
		for(var/element in splittext(new_value, "\n"))
			element = trim(element)
			if(!element)
				continue
			if(keyed && !findtext(element, " ")) // keyed_list needs "key value"; skip malformed to avoid a null-parse runtime
				continue
			if(!entry.ValidateAndSet(element))
				ok = FALSE
	else
		ok = entry.ValidateAndSet("[new_value]") // writes config_entry_value in place -> CONFIG_GET is live immediately
	if(!ok)
		.["success"] = FALSE
		.["message"] = "validation failed"
		return
	entry.modified = TRUE
	log_admin("[admin_name] (via Symphony) set config [entry.name] = [new_value] (was [old_value])")
	message_admins("[admin_name] (via Symphony) changed config [entry.name] to [entry.config_entry_value].")
	.["success"] = TRUE
	.["name"] = entry.name
	.["value"] = entry.config_entry_value
