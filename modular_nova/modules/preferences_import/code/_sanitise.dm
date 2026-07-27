/**
 * Savefile import sanitising.
 *
 * An imported savefile is hostile input, and the load path never validates - only the UI write path calls is_valid().
 * PASS 1 runs at import on the raw JSON, before any preferences datum exists: structural bounds, plus the structures
 * no deserialize() covers. Unknown keys are KEPT, because migration reads them.
 * PASS 2 runs on the next load, after migration, and rebuilds every known preference in every slot through the
 * validating write path.
 */

/// Bounds on an imported file. A one-slot export is ~31 KB, so even a full 45 slots lands well under this.
#define PREFS_IMPORT_MAX_BYTES (1024 * 1024)
/// Cap on JSON nesting depth. json_decode has no depth limit of its own.
#define PREFS_IMPORT_MAX_DEPTH 24
/// Cap on character slots in an imported file.
#define PREFS_IMPORT_MAX_SLOTS 60
/// Marks a file as awaiting the post-migration pass. Removed by pass 2.
#define PREFS_IMPORT_PENDING_KEY "babylon_import_pending"
/// Records that the one-time "you can import your characters" notice has been shown.
#define PREFS_IMPORT_NOTICE_KEY "babylon_import_notice_seen"

/**
 * Depth check on the DECODED tree, not the raw text.
 *
 * Decoding first is cheaper - json_decode is native C, and the upload limit already bounds it. Iterative with an
 * explicit stack rather than recursive, because a recursive walk over a deliberately deep tree is its own overflow.
 */
/proc/prefs_import_tree_too_deep(tree)
	if(!islist(tree))
		return FALSE
	// Parallel stacks of node and its depth - DM has no tuple.
	var/list/nodes = list(tree)
	var/list/depths = list(1)
	while(length(nodes))
		var/node = nodes[length(nodes)]
		var/depth = depths[length(depths)]
		nodes.len--
		depths.len--
		if(depth > PREFS_IMPORT_MAX_DEPTH)
			return TRUE
		if(!islist(node))
			continue
		var/list/as_list = node
		for(var/key in as_list)
			// Associative values live under the key; plain list entries ARE the key.
			var/value = key
			if(!isnum(key) && !isnull(as_list[key]))
				value = as_list[key]
			if(!islist(value))
				continue
			nodes += list(value)
			depths += depth + 1
	return FALSE

/// Structural checks on a decoded tree. Returns an error string, or null when the tree is fine.
/proc/prefs_import_prevalidate(list/json_tree, datum/preferences/prefs)
	if(!islist(json_tree) || !length(json_tree))
		return "file is empty or not a savefile"
	var/version = json_tree["version"]
	if(!isnum(version))
		return "missing version"
	// SAVEFILE_VERSION_MIN/MAX are #undef'd at the end of preferences_savefile.dm, so go through the datum's helper.
	// Below MIN the loader wipes the directory rather than migrating. Newer files pass, since pass 2 rebuilds anyway.
	if(prefs?.check_savedata_version(json_tree) == SAVE_DATA_OBSOLETE)
		return "savefile version [version] is too old to be migrated"
	var/slots = 0
	for(var/key in json_tree)
		if(findtext(key, "character") == 1)
			slots++
	if(slots > PREFS_IMPORT_MAX_SLOTS)
		return "too many character slots ([slots])"
	return null

/// PASS 1. Sanitise the structures no deserialize() protects, in place, and return the tree.
/// Does not drop unknown keys, because migration reads them.
/proc/prefs_import_pass1(list/json_tree)
	for(var/key in json_tree)
		if(findtext(key, "character") != 1)
			continue
		var/list/slot = json_tree[key]
		if(!islist(slot))
			json_tree[key] = list()
			continue
		slot["loadout_list"] = prefs_import_clean_loadout(slot["loadout_list"])
		slot["alt_job_titles"] = sanitize_alt_job_titles(slot["alt_job_titles"])
		slot["augments"] = prefs_import_clean_assoc_paths(slot["augments"])
		slot["augment_limb_styles"] = prefs_import_clean_assoc_paths(slot["augment_limb_styles"])
		slot["languages"] = prefs_import_clean_assoc_paths(slot["languages"])
	json_tree[PREFS_IMPORT_PENDING_KEY] = TRUE
	return json_tree

/// Loadout names and descriptions are free text shown to everyone who examines the item.
/// The UI writes them through tgui_input_text(encode = TRUE) and the load path does neither, so re-apply both here.
/proc/prefs_import_clean_loadout(raw)
	if(!islist(raw))
		return list()
	var/list/out = list()
	for(var/path in raw)
		var/list/details = raw[path]
		if(!islist(details))
			out[path] = list()
			continue
		var/list/clean = list()
		for(var/detail_key in details)
			var/value = details[detail_key]
			if(istext(value))
				// Match the UI's own caps so an import cannot exceed what a player could type.
				var/cap = (detail_key == INFO_DESCRIBED) ? MAX_DESC_LEN : MAX_NAME_LEN
				clean[detail_key] = copytext(html_encode(value), 1, cap)
			else if(isnum(value) || islist(value))
				clean[detail_key] = value
		out[path] = clean
	return out

/// Keep only text or path keyed entries. The owning loaders resolve them, we just guarantee the shape.
/proc/prefs_import_clean_assoc_paths(raw)
	if(!islist(raw))
		return list()
	var/list/out = list()
	for(var/key in raw)
		if(!istext(key) && !ispath(key))
			continue
		out[key] = raw[key]
	return out

/**
 * PASS 2. Runs on the next load, after migration, with a real preferences datum.
 *
 * Rebuilds every registry-known preference through write_preference(), which validates and falls back to an
 * informed default. Unrecognised keys are left alone - only out-of-range slots are dropped.
 */
/datum/preferences/proc/prefs_import_finalise()
	if(!savefile)
		return FALSE
	if(!savefile.get_entry(PREFS_IMPORT_PENDING_KEY))
		return FALSE

	var/list/player_prefs = list()
	var/list/character_prefs = list()
	for(var/key in GLOB.preference_entries_by_key)
		var/datum/preference/preference = GLOB.preference_entries_by_key[key]
		if(isnull(preference))
			continue
		switch(preference.savefile_identifier)
			if(PREFERENCE_PLAYER)
				player_prefs += preference
			if(PREFERENCE_CHARACTER)
				character_prefs += preference

	var/list/counts = list("rebuilt" = 0, "reset" = 0)

	// Player scope lives at the savefile root, so one pass covers it.
	prefs_import_rebuild(player_prefs, counts)

	// Character scope resolves through default_slot, so every slot has to be visited in turn.
	var/original_slot = default_slot
	var/slots = 0
	var/list/tree = savefile.get_entry()
	if(islist(tree))
		for(var/tree_key in tree)
			if(findtext(tree_key, "character") != 1)
				continue
			var/slot_number = text2num(copytext(tree_key, 10))
			if(!isnum(slot_number) || !islist(tree[tree_key]))
				continue
			default_slot = slot_number
			prefs_import_forget(character_prefs)
			prefs_import_strip_empty_loadout_keys(tree[tree_key])
			prefs_import_rebuild(character_prefs, counts)
			slots++

	default_slot = original_slot
	prefs_import_forget(character_prefs)
	savefile.set_entry("default_slot", original_slot)

	prefs_import_prune_unknown()
	savefile.remove_entry(PREFS_IMPORT_PENDING_KEY)
	savefile.save()

	log_game("Preferences import finalised for [parent?.ckey]: [slots] slot\s, [counts["rebuilt"]] preferences rebuilt, [counts["reset"]] reset to defaults.")
	return TRUE

/// Round-trips each preference through the validating write path, counting into an assoc of tallies.
/datum/preferences/proc/prefs_import_rebuild(list/preferences, list/counts)
	for(var/datum/preference/preference as anything in preferences)
		var/value
		var/usable = FALSE
		try
			value = read_preference(preference.type)
			usable = !isnull(value) && preference.is_valid(value, src)
		catch
			usable = FALSE
		var/written
		if(usable)
			// Serialise on the way back in - write_preference deserialises, and read_preference already gave us that.
			written = write_preference(preference, preference.serialize(value))
		else
			written = write_preference(preference, preference.create_informed_default_value(src))
			counts["reset"]++
		if(written)
			counts["rebuilt"]++

/// Drops cached character values so the next read resolves against the slot default_slot now points at.
/datum/preferences/proc/prefs_import_forget(list/preferences)
	for(var/datum/preference/preference as anything in preferences)
		value_cache -= preference.type

/// Migration leaves a null key behind for any loadout path it cannot resolve, and that makes
/// sanitize_loadout_list stack_trace on every read. Drop them before the rebuild reads the list.
/proc/prefs_import_strip_empty_loadout_keys(list/slot)
	var/list/loadout = slot["loadout_list"]
	if(!islist(loadout))
		return
	var/list/clean = list()
	for(var/path in loadout)
		if(isnull(path) || (istext(path) && !length(path)))
			continue
		clean[path] = loadout[path]
	if(length(clean) != length(loadout))
		slot["loadout_list"] = clean

/**
 * Drops character slots whose number is out of range, and NOTHING else.
 *
 * Unrecognised keys stay, and must keep staying. The savefile is only ever read by name, so a key nobody asks for
 * is inert, and file size is already bounded by PREFS_IMPORT_MAX_BYTES at import time.
 *
 * Slot numbers are different, because load_preferences derives max_save_slots by SCANNING these key names. That is
 * a real read path, so an injected "character99999999" would take effect rather than sit inert.
 */
/datum/preferences/proc/prefs_import_prune_unknown()
	var/list/tree = savefile.get_entry()
	if(!islist(tree))
		return
	var/list/dropped = list()

	for(var/key in tree)
		if(findtext(key, "character") != 1)
			continue
		var/slot_number = text2num(copytext(key, 10))
		if(isnum(slot_number) && slot_number >= 1 && slot_number <= PREFS_IMPORT_MAX_SLOTS)
			continue
		dropped += key

	for(var/key in dropped)
		tree -= key

	if(!length(dropped))
		return
	log_game("Preferences import dropped [length(dropped)] out-of-range character slot\s for [parent?.ckey]: [jointext(dropped, ", ")]")

// Deliberately not #undef'd: the import verb in this module reads the byte and depth bounds.
