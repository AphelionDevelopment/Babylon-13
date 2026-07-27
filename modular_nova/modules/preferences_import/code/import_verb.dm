/**
 * Player-facing preferences import, for people bringing a character across from another server.
 *
 * Restricted to players holding the in-game whitelist role. That is not the security boundary (the
 * sanitiser is), but it keeps the surface to accounts that have already linked a Discord identity and
 * been granted access, which makes abuse attributable.
 *
 * Always imports over the CALLER's own savefile. There is no target parameter, so unlike the admin verb
 * this cannot be pointed at somebody else.
 */
/client/proc/import_preferences()
	set name = "Import Preferences"
	set desc = "Upload a character preferences JSON file, replacing your current one."
	set category = "OOC"

	if(CONFIG_GET(flag/forbid_preferences_import))
		to_chat(src, span_warning("Preference importing is disabled on this server."))
		return

	if(!prefs)
		to_chat(src, span_warning("Your preferences are not loaded yet. Try again in a moment."))
		return

	if(is_guest_key(key)) // `key`, not `ckey` - ckey() strips the hyphen that is_guest_key matches on
		to_chat(src, span_warning("Guest accounts cannot import preferences."))
		return

	// Whitelisted players only, using the ENTITLEMENT form. Fail-closed on both a database problem and a
	// disabled module: the gate form returns TRUE when Symphony is off, which handed this verb to every
	// player on a stock server - the exact inverse of what this file documents.
	if(!symphony_holds_whitelist_role(ckey))
		to_chat(src, span_warning("Importing preferences is only available to whitelisted players."))
		return

	var/cooldown = CONFIG_GET(number/seconds_cooldown_for_preferences_import)
	if(world.time < next_preferences_import)
		var/wait_seconds = round((next_preferences_import - world.time) / 10)
		to_chat(src, span_warning("Please wait [wait_seconds] more second\s before importing again."))
		return

	to_chat(src, span_boldwarning("This REPLACES all of your current characters with the contents of the uploaded file."))
	var/confirm = tgui_alert(
		mob,
		"Replace all of your characters with an uploaded file? A backup of your current preferences is kept. You will be disconnected to finish.",
		"Import Preferences",
		list("Import", "Cancel"),
	)
	if(confirm != "Import")
		return

	// Re-check after the prompt: the player may have been sitting on the dialog.
	if(!symphony_holds_whitelist_role(ckey) || CONFIG_GET(flag/forbid_preferences_import))
		to_chat(src, span_warning("Importing is no longer available."))
		return

	var/uploaded_file = input(mob, "Choose a preferences JSON file", "Import Preferences") as null|file
	if(!isfile(uploaded_file) || !length(uploaded_file))
		return

	next_preferences_import = world.time + (cooldown SECONDS)

	if(!findtext("[uploaded_file]", ".json", -5))
		to_chat(src, span_warning("That is not a .json file."))
		return

	var/filesize = length(uploaded_file)
	if(filesize > PREFS_IMPORT_MAX_BYTES)
		to_chat(src, span_warning("That file is too large ([filesize] bytes; the limit is [PREFS_IMPORT_MAX_BYTES])."))
		return

	var/raw = file2text(uploaded_file)
	if(!length(raw))
		to_chat(src, span_warning("That file was empty or unreadable."))
		return

	// Depth is checked before decoding: json_decode has no depth limit and a nested payload would be
	// parsed on the login tick.
	if(prefs_import_too_deep(raw))
		to_chat(src, span_warning("That file is nested too deeply to be a preferences file."))
		log_admin("[key_name(src)] attempted a preferences import with excessive JSON nesting.")
		return

	var/list/json_tree
	try
		json_tree = json_decode(raw)
	catch(var/exception/err)
		to_chat(src, span_warning("That file is not valid JSON."))
		log_game("Preferences import by [ckey] failed to parse: [err]")
		return

	var/problem = prefs_import_prevalidate(json_tree, prefs)
	if(problem)
		to_chat(src, span_warning("That file was rejected: [problem]."))
		return

	json_tree = prefs_import_pass1(json_tree)

	var/folder_path = "data/player_saves/[ckey[1]]/[ckey]"
	var/savefile_path = "[folder_path]/preferences.json"

	if(!prefs_import_backup(savefile_path))
		to_chat(src, span_warning("Could not back up your existing preferences. Nothing was changed."))
		return

	fdel(savefile_path)
	fdel("[savefile_path].updatebac") // else load_preferences can revert to a stale migration backup
	text2file(json_encode(json_tree), file(savefile_path))

	// Drop the cached datum so the file is re-read. The still-connected client would otherwise write its
	// stale in-memory preferences back over the import.
	GLOB.preferences_datums[ckey] = null

	log_admin("[key_name(src)] imported their own preferences ([filesize] bytes).")
	message_admins("[key_name(src)] imported their own preferences via the whitelisted-player import.")

	to_chat(src, span_boldnotice("Preferences imported. You will be disconnected now; reconnect to finish."))
	to_chat(src, span_notice("Anything the server could not accept will be reset to a default when you return."))
	QDEL_IN(src, 2)

/**
 * Copy the current savefile aside as a pruning ring buffer. Unlike the admin verb, which refuses the
 * import once its backup limit is reached, this discards the oldest so a player can never lock
 * themselves out of importing.
 */
/proc/prefs_import_backup(savefile_path)
	if(!fexists(savefile_path))
		return TRUE // nothing to back up, which is fine
	var/limit = CONFIG_GET(number/preferences_import_backup_limit)
	var/list/existing = list()
	for(var/i = 1 to limit)
		var/candidate = "[savefile_path].importbac-[i]"
		if(fexists(candidate))
			existing += candidate
	// Ring buffer: once full, drop the oldest and shuffle the rest down.
	if(length(existing) >= limit)
		fdel("[savefile_path].importbac-1")
		for(var/i = 2 to limit)
			var/from_path = "[savefile_path].importbac-[i]"
			if(!fexists(from_path))
				continue
			fcopy(from_path, "[savefile_path].importbac-[i - 1]")
			fdel(from_path)
	var/slot = min(length(existing) + 1, limit)
	return fcopy(savefile_path, "[savefile_path].importbac-[slot]")

/client
	/// world.time before which this client may not import preferences again.
	var/next_preferences_import = 0
