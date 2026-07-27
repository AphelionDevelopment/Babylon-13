/**
 * Whitelist enforcement toggle.
 *
 * This file used to expose a general-purpose config read and write pair: every non-hidden, non-locked
 * entry in the game's whole config namespace was live-writable by any comms-key holder, filtered only
 * by a name-substring deny-list. That design fails open on every entry upstream adds, and it did:
 * admin_2fa_url (remote deadmin, plus an attacker URL rendered into every admin's chat where a 2FA link
 * is expected), panic_bunker with panic_server_address (redirect every new connector to another
 * server), and the ipintel_* family (real-time player IP exfiltration and control over who may connect
 * at all) were all reachable, and none of them existed when the deny-list was written.
 *
 * The general editor is gone. Game config belongs to TGS and the config files. What remains is the one
 * switch the panel genuinely needs to flip quickly, hardcoded to a single entry name so there is no
 * namespace to walk.
 */

/// Turn the whitelist gate on or off at runtime. The panel also persists it to file for the next boot.
/datum/world_topic/symphony_set_enforcement
	keyword = "symphony_set_enforcement"
	require_comms_key = TRUE

/datum/world_topic/symphony_set_enforcement/Run(list/input)
	. = list()
	// Deliberately NOT behind symphony_enabled, unlike every other topic in the module: this is the topic
	// that turns that flag on, so gating it on the flag would make enforcement impossible to enable.
	var/admin_name = input["admin_name"] || "Discord Admin"
	var/raw = input["enabled"]
	if(isnull(raw))
		.["success"] = FALSE
		.["message"] = "missing enabled"
		return
	var/enabled = (raw == "1" || raw == "true" || raw == 1)

	// Hardcoded entry name. There is deliberately no way to name a different one: that was the defect.
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
