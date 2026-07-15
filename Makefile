.PHONY: sync-shared format check publish clean

MODS := WeaponStats EnemyStats CombatStats
SHARED_DIR := scripts/shared

# Copy scripts/shared/*.lua into each mod's scripts/mods/<mod>/shared/ folder.
# Run before testing locally; CI does the same before zipping.
sync-shared:
	@for mod in $(MODS); do \
		dest="$$mod/scripts/mods/$$mod/shared"; \
		mkdir -p "$$dest"; \
		cp $(SHARED_DIR)/*.lua "$$dest/"; \
		echo "synced -> $$dest"; \
	done

# Format all Lua files with StyLua.
format:
	stylua .

# Check formatting without modifying.
check:
	stylua --check .

# Publish mods to Nexus Mods (see scripts/ci/publish_mods.js for options).
# Syncs shared files first, then uploads, then cleans up.
publish:
	$(MAKE) sync-shared
	node scripts/ci/publish_mods.js $(ARGS)
	$(MAKE) clean

# Remove copied shared files from mod folders.
clean:
	@for mod in $(MODS); do \
		rm -rf "$$mod/scripts/mods/$$mod/shared"; \
	done
