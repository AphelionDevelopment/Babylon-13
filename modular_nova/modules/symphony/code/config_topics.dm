/// Entries that carry a credential but are NOT marked CONFIG_ENTRY_HIDDEN upstream - webhook URLs are
/// bearer tokens in a URL, so exposing one lets the holder post as the server (or redirect adminhelps).
/// Matched by name so a new entry of the same shape is covered without needing an upstream change.
/proc/symphony_config_is_secret(entry_name)
	return findtext(entry_name, "webhook") \
		|| findtext(entry_name, "password") \
		|| findtext(entry_name, "passwd") \
		|| findtext(entry_name, "secret") \
		|| findtext(entry_name, "token") \
		|| findtext(entry_name, "comms_key") \
		|| findtext(entry_name, "invoke_") \
		|| findtext(entry_name, "_key")

/// Read all NON-hidden game config entries so the panel can list and edit them. Optional `filter` narrows by name.
/datum/world_topic/symphony_config_get
	keyword = "symphony_config_get"
	require_comms_key = TRUE
	log = FALSE

/datum/world_topic/symphony_config_get/Run(list/input)
	. = list()
	// Behind the master switch like every other file in the module. Without this, "the bridge is inert
	// until you enable it" was false for its highest-value surface: an operator who compiled the module
	// but left symphony_enabled off still exposed live config read AND write.
	if(!CONFIG_GET(flag/symphony_enabled))
		.["error"] = "symphony is disabled on this server"
		return
	var/filter = LOWER_TEXT(trim(input["filter"]))
	// Deliberate audit line. The WRITE topic logs three ways; the read that maps the namespace for it
	// logged nothing, so post-incident nobody could tell whether reconnaissance had happened.
	log_admin("Symphony: config list read via topic[filter ? " (filter: [filter])" : ""].")
	var/list/entries = list()
	for(var/entry_name in global.config.entries)
		if(filter && !findtext(entry_name, filter))
			continue
		var/datum/config_entry/entry = global.config.entries[entry_name]
		if(entry.protection & CONFIG_ENTRY_HIDDEN) // never expose comms_key / DB creds
			continue
		if(symphony_config_is_secret(entry_name)) // webhook URLs etc. aren't HIDDEN upstream but are secrets
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
	// Master switch, as on the read topic. This is the module's most dangerous surface and it was the
	// only one running on a server that never enabled the bridge.
	if(!CONFIG_GET(flag/symphony_enabled))
		.["success"] = FALSE
		.["message"] = "symphony is disabled on this server"
		return
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
	// A world_topic is NOT an admin proccall, so protection is NOT auto-guarded - enforce here.
	// HIDDEN must never be touched. LOCKED can't be changed live (the SSymphony file write persists it for next boot).
	if(entry.protection & CONFIG_ENTRY_HIDDEN)
		.["success"] = FALSE
		.["message"] = "hidden entry"
		return
	if(symphony_config_is_secret(entry_name))
		.["success"] = FALSE
		.["message"] = "protected entry"
		return
	if(entry.protection & CONFIG_ENTRY_LOCKED)
		.["success"] = FALSE
		.["message"] = "locked - change persisted to file, applies on restart"
		return
	var/old_value = entry.config_entry_value
	var/ok = FALSE
	if(istype(entry, /datum/config_entry/number_list))
		// number_list REPLACES the whole value on each call - pass everything as one space-separated line.
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
			// keyed_list needs "key value". A line without a separator used to be skipped silently, which
			// reported success while quietly dropping it - refuse the whole write instead.
			if(keyed && !findtext(element, " "))
				ok = FALSE
				break
			if(!entry.ValidateAndSet(element))
				ok = FALSE
				break
		// The live list was emptied before validating, so a rejected line must not leave it truncated.
		if(!ok)
			entry.config_entry_value = old_value
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
