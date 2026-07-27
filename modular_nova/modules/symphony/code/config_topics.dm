// The rest of the game config belongs to TGS and the config files. This is the one switch the panel gets.

/// Turn the whitelist gate on or off at runtime. The panel also persists it to file for the next boot.
/datum/world_topic/symphony/set_enforcement
	keyword = "symphony_set_enforcement"
	require_comms_key = TRUE

/datum/world_topic/symphony/set_enforcement/Run(list/input)
	. = list()
	// Deliberately not behind symphony_enabled, unlike the rest of the module - this is what turns that flag on.
	var/admin_name = input["admin_name"] || "Discord Admin"
	var/raw = input["enabled"]
	if(isnull(raw))
		.["success"] = FALSE
		.["message"] = "missing enabled"
		return
	var/enabled = (raw == "1" || raw == "true" || raw == 1)

	// Hardcoded entry name - there is deliberately no way to ask for a different one.
	var/datum/config_entry/entry = global.config.entries["symphony_enabled"]
	if(!entry)
		.["success"] = FALSE
		.["message"] = "symphony_enabled is not a known config entry on this server"
		return

	var/old_value = entry.config_entry_value
	if(!entry.ValidateAndSet(enabled ? "1" : "0"))
		.["success"] = FALSE
		.["message"] = "the game refused the value"
		return

	.["success"] = TRUE
	.["enabled"] = enabled
	log_admin("[admin_name] (via Symphony) set whitelist enforcement to [enabled ? "on" : "off"] (was [old_value]).")
	message_admins("[html_encode(admin_name)] (via Symphony) turned whitelist enforcement [enabled ? "ON" : "OFF"].")
