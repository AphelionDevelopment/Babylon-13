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
 *    preferences datum exists. It rebuilds every registry-known preference through the validating
 *    write path and drops keys that are neither a known preference nor structural.
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

/// Top-level keys that are not /datum/preference backed but are legitimately part of a savefile.
GLOBAL_LIST_INIT(prefs_import_player_keys, list(
	"version",
	"default_slot",
	PREFS_IMPORT_PENDING_KEY,
))

/// Per-character-slot keys that are not /datum/preference backed.
GLOBAL_LIST_INIT(prefs_import_character_keys, list(
	"modular_version",
	"tgui_prefs_migration",
	"randomise",
	"all_quirks",
	"job_preferences",
	"languages",
	"augments",
	"augment_limb_styles",
	"body_markings",
	"food_preferences",
	"loadout_list",
	"alt_job_titles",
	"mismatched_customization",
	"allow_advanced_colors",
	"hairstyle_name",
))

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
 * validates via is_valid() before writing, replacing anything invalid with an informed default. Then
 * drops keys that are neither a known preference nor structural, which is safe now because migration
 * has already consumed the legacy keys it needed.
 */
/datum/preferences/proc/prefs_import_finalise()
	if(!savefile)
		return FALSE
	if(!savefile.get_entry(PREFS_IMPORT_PENDING_KEY))
		return FALSE

	var/rebuilt = 0
	var/reset = 0
	for(var/key in GLOB.preference_entries_by_key)
		var/datum/preference/preference = GLOB.preference_entries_by_key[key]
		if(isnull(preference))
			continue
		var/value
		try
			value = read_preference(preference.type)
		catch
			value = null
		if(isnull(value) || !preference.is_valid(value, src))
			value = preference.create_informed_default_value(src)
			reset++
		if(write_preference(preference, value))
			rebuilt++

	prefs_import_prune_unknown()
	savefile.remove_entry(PREFS_IMPORT_PENDING_KEY)
	savefile.save()

	log_game("Preferences import finalised for [parent?.ckey]: [rebuilt] preferences rebuilt, [reset] reset to defaults.")
	return TRUE

/// Removes savefile keys that are neither a registered preference nor a known structural key.
/datum/preferences/proc/prefs_import_prune_unknown()
	var/list/tree = savefile.get_entry()
	if(!islist(tree))
		return
	for(var/key in tree)
		if(findtext(key, "character") == 1)
			var/list/slot = tree[key]
			if(!islist(slot))
				continue
			for(var/slot_key in slot)
				if(GLOB.preference_entries_by_key[slot_key])
					continue
				if(slot_key in GLOB.prefs_import_character_keys)
					continue
				slot -= slot_key
			continue
		if(GLOB.preference_entries_by_key[key])
			continue
		if(key in GLOB.prefs_import_player_keys)
			continue
		tree -= key

// Deliberately not #undef'd: the import verb in this module reads the byte and depth bounds.
