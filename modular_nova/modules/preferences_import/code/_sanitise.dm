/**
 * Savefile import sanitising.
 *
 * A savefile that arrives from outside is hostile input. The preference system validates on the UI path
 * (`write()` calls `is_valid()`) but NOT on the load path (`read()` only calls `deserialize()`), so an
 * uploaded file otherwise reaches the game with every entitlement and format check bypassed.
 *
 * Two passes, because the checks need different things:
 *
 *  - PASS 1 runs at import time on the raw JSON tree. There is no /datum/preferences for the target
 *    player yet, so `is_valid()` (which many implementations resolve against a preferences datum) cannot
 *    run. Pass 1's job is to make the file safe to LOAD: structural bounds, plus the handful of
 *    structures that live outside the /datum/preference type system and therefore get no deserialize()
 *    sanitising at all. Unknown keys are KEPT, because savefile migration legitimately reads keys that
 *    no longer correspond to a preference.
 *
 *  - PASS 2 runs on the next load, after migration has brought the file up to date and a real
 *    preferences datum exists. It rebuilds every registry-known preference, in every character slot,
 *    through the validating write path. It does NOT delete unrecognised keys: see
 *    prefs_import_prune_unknown for why that was removed.
 */

/// Bounds on an imported file. The 2 MB config default is far larger than any real export: a one-slot
/// export measures ~31 KB, so even a full 45 slots lands well under this.
#define PREFS_IMPORT_MAX_BYTES (1024 * 1024)
/// Refuse absurdly nested JSON before it reaches json_decode, which has no depth limit of its own.
#define PREFS_IMPORT_MAX_DEPTH 24
/// Cap on character slots in an imported file.
#define PREFS_IMPORT_MAX_SLOTS 60
/// Marks a file as awaiting the post-migration pass. Removed by pass 2.
#define PREFS_IMPORT_PENDING_KEY "babylon_import_pending"
/// Records that the one-time "you can import your characters" notice has been shown.
#define PREFS_IMPORT_NOTICE_KEY "babylon_import_notice_seen"

/**
 * Cheap nesting-depth scan over the raw text, run BEFORE json_decode.
 * Returns the maximum bracket depth found. A deeply nested payload is a decode-time denial of service
 * on the login tick, and the existing admin import path bounds only total file size.
 */
/proc/prefs_import_max_depth(text)
	var/depth = 0
	var/highest = 0
	var/in_string = FALSE
	var/escaped = FALSE
	for(var/i = 1 to length(text))
		var/char = copytext_char(text, i, i + 1)
		if(escaped)
			escaped = FALSE
			continue
		if(char == "\\")
			escaped = TRUE
			continue
		if(char == "\"")
			in_string = !in_string
			continue
		if(in_string)
			continue
		if(char == "{" || char == "\[")
			depth++
			highest = max(highest, depth)
		else if(char == "}" || char == "]")
			depth--
	return highest

/// TRUE when the raw text nests more deeply than an imported savefile is allowed to.
/// A proc rather than a bare define comparison so callers in modules that sort before this one (the
/// admin import verb) can use it; #defines are include-order sensitive, procs are not.
/proc/prefs_import_too_deep(text)
	return prefs_import_max_depth(text) > PREFS_IMPORT_MAX_DEPTH

/**
 * Structural checks on a decoded tree. Returns an error string, or null when the tree is acceptable.
 * These are the bounds that do not need any knowledge of individual preferences.
 */
/proc/prefs_import_prevalidate(list/json_tree, datum/preferences/prefs)
	if(!islist(json_tree) || !length(json_tree))
		return "file is empty or not a savefile"
	var/version = json_tree["version"]
	if(!isnum(version))
		return "missing version"
	// SAVEFILE_VERSION_MIN/MAX are #undef'd at the end of preferences_savefile.dm, so go through the
	// datum's own helper. Below MIN the loader would wipe the directory outright rather than migrate.
	// A file from a NEWER build is allowed through: migration will not run for it, but pass 2 rebuilds
	// every preference and prunes unrecognised keys regardless.
	if(prefs?.check_savedata_version(json_tree) == SAVE_DATA_OBSOLETE)
		return "savefile version [version] is too old to be migrated"
	var/slots = 0
	for(var/key in json_tree)
		if(findtext(key, "character") == 1)
			slots++
	if(slots > PREFS_IMPORT_MAX_SLOTS)
		return "too many character slots ([slots])"
	return null

/**
 * PASS 1. Sanitise the structures that no deserialize() protects, in place, and return the tree.
 * Deliberately conservative: it does not drop unknown keys, because migration reads them.
 */
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

/**
 * Loadout entries carry free-text name and description that are applied to the spawned item and shown
 * to everyone who examines it. The UI path writes them through tgui_input_text(encode = TRUE), which
 * html-encodes and length-caps; the load path does neither, so an imported file can inject markup into
 * every examiner's chat. Re-apply both here.
 */
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

/// Keep only text-keyed entries, dropping anything structurally wrong. The owning loaders resolve these
/// against their own globals; this only guarantees they receive a list of the shape they expect.
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
 * Rebuilds every registry-known preference through write_preference(), which deserialises and then
 * validates via is_valid() before writing, replacing anything invalid with an informed default.
 * Unrecognised keys are left alone; only out-of-range character slots are dropped.
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

	// Character scope resolves through default_slot, so each slot has to be visited in turn. Rebuilding
	// once would validate only the default slot and leave every other character on pass 1 alone.
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
			// Serialise on the way back in: write_preference deserialises, and read_preference already
			// handed back the deserialised form.
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

/**
 * Savefile migration turns a loadout path it can no longer resolve into a null key, because
 * update_character_nova does `save_loadout[_text2path(loadout)] = entry` without checking the result.
 * That key then makes sanitize_loadout_list stack_trace on every read. Migration has already run by the
 * time we get here, so drop those keys before the rebuild reads the list.
 */
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
 * This deliberately does not remove unrecognised keys, and it must stay that way. Earlier versions
 * dropped any key that was neither a registered preference nor on a hand-maintained whitelist. That
 * whitelist was wrong three times running, and each time it silently destroyed real player data: first
 * keybindings, chat toggles and the ignore list, then the per-slot `version` (which made every imported
 * character fail to load and get replaced by a random one), along with scars, body features, food
 * preferences and much else.
 *
 * The reasoning that justified pruning was wrong. An unrecognised key is INERT: the savefile is only
 * ever read by name, via get_entry("...") or save_data["..."], so a key nobody asks for is never read
 * and cannot do anything. Pruning bought no safety at all, while carrying unbounded blast radius that
 * grows every time upstream adds a savefile key we do not know about. File size is already bounded by
 * PREFS_IMPORT_MAX_BYTES at import time.
 *
 * Slot numbers are different, and are still checked, because load_preferences derives max_save_slots by
 * SCANNING these key names. That is a genuine read path, so an injected "character99999999" would take
 * effect rather than sit inert.
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
