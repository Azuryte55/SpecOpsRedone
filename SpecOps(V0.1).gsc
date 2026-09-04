// Black Ops II single-player Strike Force reinforcement shop.
//
// Shop prices:
//   Random normal/heavy allied infantry = 400 (maximum four squads)
//   A.G.R. / A.S.D.                    = 700 (maximum three)
//   C.L.A.W.                           = 1500 (maximum two)
// Allied Dragonfires are not sold. A two-drone squad arrives automatically
// every two minutes by the normal cargo-VTOL delivery, with four active maximum.
//
// Enemy death rewards:
//   Infantry/other = 100, Dragonfire = 50, A.G.R. = 200, C.L.A.W. = 300.
//
// Scorestreak tab:
//   Juggernog = 2500, Double Tap = 2000.
// Head, helmet and neck hits deal no damage to infantry on either team.
//
// The player has infinite reserve ammunition for conventional firearms only;
// explosive weapons consume ammo normally.
//
// Enemy infantry enters on foot from the Drone map's outside-map ground spawn
// points. Allied infantry still uses FASTROPE_HELO. A.G.R., Dragonfire and
// C.L.A.W. use CARGO_VTOL. The shop starts with 500 points and only initializes
// on the Strike Force Drone mission. Aim + Melee opens it; Melee goes back or
// exits, and Left/Right changes tabs.
// Automatic allied Dragonfires use stock path routing, cruise at one third
// speed and slow to one fifth speed while attacking. They expire three minutes
// after unloading. Infantry on both teams engages from much farther away,
// cannot physically block the player and does not rush into melee range.
// Enemy A.G.R.s continuously rush the closest opposing combatant. Allied
// A.G.R.s attack only enemies they can currently see and otherwise wander
// between valid Drone-map objectives. Both teams move at 2x stock speed.
// Allied C.L.A.W. miniguns deal half damage.
// Enemy wave spawn scale with campaign difficulty: Recruit 0.5x,
// Regular 1x, Hardened 1.5x and Veteran 2.5x.

// Infinity Loader's BO2 single-player template enters through init().
// Keep main() as well so this source remains compatible with T6SP-Mod.
init()
{
    level thread sfmenu_bootstrap();
}

main()
{
    level thread sfmenu_bootstrap();
}

sfmenu_bootstrap()
{
    // Some loaders may invoke both exported entry points.
    if ( isDefined( level.sfmenu_boot_started ) )
    {
        return;
    }
    level.sfmenu_boot_started = 1;

    mapname = getdvar( "mapname" );
    if ( !sfmenu_is_strike_force_map( mapname ) )
    {
        return;
    }

    // A custom script can enter before the stock RTS scripts finish.
    while ( !isDefined( level.rts ) )
    {
        wait 0.1;
    }

    while ( !isDefined( level.rts.player ) || !isDefined( level.rts.packages ) || !isDefined( level.rts.transport ) || !isDefined( level.rts.keyactions ) || !isDefined( level.rts.game_rules ) )
    {
        wait 0.1;
    }

    level.sfmenu = spawnstruct();
    level.sfmenu.open = 0;
    level.sfmenu.selection = 0;
    level.sfmenu.tab = 0;
    level.sfmenu.points = 500;
    level.sfmenu.reward_queue = [];
    level.sfmenu.hud = [];
    level.sfmenu.items = [];
    level.sfmenu.saved_bindings = [];
    level.sfmenu.purchase_in_progress = 0;
    level.sfmenu.shop_lock_enabled = 0;
    level.sfmenu.active_infantry_squads = 0;
    level.sfmenu.active_agr = 0;
    level.sfmenu.active_claw = 0;
    level.sfmenu.dragonfire_spawn_interval = 120;
    level.sfmenu.dragonfire_lifetime = 180;
    level.sfmenu.max_allied_dragonfires = 4;
    level.sfmenu.enemy_soldier_spawn_interval = 2000;
    level.sfmenu.next_enemy_soldier_spawn_time = 0;
    level.sfmenu.allied_dragonfire_max_speed = 10;
    level.sfmenu.allied_dragonfire_aggro_max_speed = 6;
    // Stock A.G.R. overrides are 22 maximum / 12 AI movement speed. These are
    // half of the previous 4x boost, leaving the A.G.R.s at 2x stock speed.
    level.sfmenu.agr_max_speed = 44;
    level.sfmenu.agr_ai_max_speed = 24;
    level.sfmenu.soldier_attack_distance = 4096;
    level.sfmenu.allied_claw_minigun_scale = 0.5;
    level.sfmenu.enemy_post_land_protection = 3;
    level.sfmenu.enemy_stuck_timeout = 60;
    level.sfmenu.ally_stuck_timeout = 20;
    level.sfmenu.ai_watchdog_interval = 5;
    level.sfmenu.ai_freeze_timeout = 30;
    level.sfmenu.ai_recovery_cooldown = 10000;
    level.sfmenu.juggernog = 0;
    level.sfmenu.double_tap = 0;
    level.sfmenu.max_active_deliveries = 5;
    level.sfmenu.enemy_spawn_multiplier = sfshop_get_enemy_spawn_multiplier();
    level.sfmenu.wave_number = 0;
    level.sfmenu.wave5_agrs_killed = 0;
    level.sfmenu.wave5_claws_killed = 0;
    level.sfmenu.wave5_claw_total = 3;
    level.sfmenu.wave5_claws_unlocked = 0;
    level.sfmenu.enemy_ground_spawn_index = -1;
    level.sfmenu.allow_mission_complete = 0;
    level.sfmenu.original_mission_complete = level.custom_mission_complete;
    // T6 SP has a global pool of 2048 game entities. Keep a safety reserve for
    // transports, projectiles, mission triggers and other short-lived objects.
    level.sfmenu.entity_limit = 2048;
    level.sfmenu.entity_reserve = 300;
    level.sfmenu.spawn_pause_threshold = 300;
    level.sfmenu.purchase_block_threshold = 200;
    level.sfmenu.free_entities = level.sfmenu.entity_limit;
    level.sfmenu.entity_warning_shown = 0;
    level.sfmenu.entity_cleanup_started = 0;

    // Keep the stock package at two drones. Its unload code uses overlapping
    // batches when the array is enlarged. Automatic allied deliveries use the
    // stock pair; enemy wave callbacks safely expand their squads to exactly ten.
    sfshop_configure_dragonfire_package();
    // Keep one enemy infantry package at two soldiers. The stock package sizes
    // can otherwise leave an unfillable remainder after the greedy wave picker.
    sfshop_configure_wave_infantry_package();
    // Four corpses is enough to preserve the short death animation while
    // preventing long endless sessions from retaining a large corpse pool.
    setdvar( "ai_corpseCount", 4 );

    // Never use zero here. The stock timer thread may already have passed its
    // initial check; waking that thread with a zero value can instantly report
    // a failed mission. Use a very long overflow-safe value and cancel its HUD.
    level.rts.game_rules.time = 30000;
    level thread sfshop_remove_time_limits();
    level thread sfshop_endless_outcome_guard();

    while ( !common_scripts\utility::flag( "start_rts" ) )
    {
        wait 0.1;
    }

    // Aim + Melee opens the shop. Both a tap and a hold are accepted so the
    // chord behaves consistently on controller and keyboard bindings.
    if ( isDefined( level.rts.keyactions[ "BUTTON_RSTICK" ] ) )
    {
        level.sfmenu.saved_melee_binding = level.rts.keyactions[ "BUTTON_RSTICK" ];
    }
    if ( isDefined( level.rts.keyactions[ "BUTTON_RSTICK_LONG" ] ) )
    {
        level.sfmenu.saved_melee_long_binding = level.rts.keyactions[ "BUTTON_RSTICK_LONG" ];
    }

    melee_callback = ::sfmenu_melee;
    maps\_so_rts_support::registerkeybinding( "BUTTON_RSTICK", melee_callback, "short" );
    maps\_so_rts_support::registerkeybinding( "BUTTON_RSTICK_LONG", melee_callback, "long" );

    sfshop_create_points_hud();
    level thread sfshop_reward_processor();
    level thread sfshop_entity_capacity_monitor();
    level thread sfshop_entity_monitor();
    level thread sfshop_ai_freeze_watchdog();
    level thread sfshop_accelerate_delivery_transports();
    level thread sfshop_dropped_weapon_monitor();
    level thread sfshop_remove_freecam_filter();
    level thread sfshop_suppress_drone_warning_beep_loop();
    level thread sfshop_suppress_enemy_arrival_hud();
    level thread sfshop_enemy_spawn_controller();
    level thread sfshop_disable_free_reinforcements();
    level thread sfshop_automatic_dragonfire_reinforcements();
    level thread sfshop_player_infinite_ammo();

    level endon( "rts_terminated" );

    while ( 1 )
    {
        wait 1;
    }
}

sfmenu_is_strike_force_map( mapname )
{
    return mapname == "so_rts_mp_drone";
}

// Prevent only the stock ten-second visor warning beep. Do not touch snddamage
// or the POI alarm RPCs: those are the map-native objective-under-attack sounds.
sfshop_suppress_drone_warning_beep_loop()
{
    level endon( "rts_terminated" );
    wait 2;

    while ( 1 )
    {
        sfshop_mark_drone_poi_warning_seen( "rts_obj_silo" );
        sfshop_mark_drone_poi_warning_seen( "rts_poi_dish" );
        sfshop_mark_drone_poi_warning_seen( "rts_poi_eletrical_transformer" );
        wait 0.5;
    }
}

// Hide the stock Drone-mission enemy-arrival countdown and prevent the stock
// package system from queuing "enemy forces arrived" banners. The custom wave
// HUD uses separate elements, so it remains visible.
sfshop_suppress_enemy_arrival_hud()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        // units_delivered only queues its enemy banner after this timestamp.
        level.rts.enemy_notification = getTime() + 60000;
        if ( !common_scripts\utility::flag( "start_rts_enemy" ) )
        {
            level.rts.player notify( "kill_countdown" );
            level notify( "kill_countdown" );
            maps\_so_rts_support::time_countdown_delete();
        }
        wait 0.1;
    }
}

sfshop_mark_drone_poi_warning_seen( poi_ref )
{
    poi = maps\_so_rts_poi::getpoibyref( poi_ref );
    if ( !isDefined( poi ) )
    {
        return;
    }

    poi.warning = 1;
}

// Refill the human player's equipped weapon. The SP VM's full-inventory query
// is unsafe here, so weapon switches are handled naturally by this loop.
sfshop_player_infinite_ammo()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        player = level.rts.player;
        if ( isDefined( player ) )
        {
            weapon = player getcurrentweapon();
            if ( isDefined( weapon ) && weapon != "" && weapon != "none" && !sfshop_weapon_uses_limited_explosive_ammo( weapon ) )
            {
                player givemaxammo( weapon );
            }
        }
        wait 0.2;
    }
}

sfshop_weapon_uses_limited_explosive_ammo( weapon )
{
    weapon_class = weaponclass( weapon );
    if ( weapon_class == "grenade" || weapon_class == "rocketlauncher" )
    {
        return 1;
    }

    // Covers explosive rifles/bolts and custom weapon aliases whose class is
    // reported as rifle or inventory instead of grenade/rocketlauncher.
    return isSubStr( weapon, "explosive" ) || isSubStr( weapon, "grenade" ) || isSubStr( weapon, "rocket" ) || isSubStr( weapon, "missile" ) || isSubStr( weapon, "launcher" ) || isSubStr( weapon, "crossbow" ) || isSubStr( weapon, "rpg" ) || isSubStr( weapon, "smaw" ) || isSubStr( weapon, "m32" ) || isSubStr( weapon, "xm25" ) || isSubStr( weapon, "war_machine" ) || isSubStr( weapon, "china_lake" ) || isSubStr( weapon, "m202" ) || isSubStr( weapon, "fhj" ) || isSubStr( weapon, "javelin" ) || isSubStr( weapon, "claymore" ) || isSubStr( weapon, "semtex" ) || isSubStr( weapon, "satchel" ) || isSubStr( weapon, "titus" ) || isSubStr( weapon, "ray_gun" ) || isSubStr( weapon, "raygun" );
}

sfshop_configure_dragonfire_package()
{
    pkg = maps\_so_rts_catalog::package_getpackagebytype( "quadrotor_pkg" );
    if ( !isDefined( pkg ) || !isDefined( pkg.units ) || pkg.units.size == 0 )
    {
        return;
    }

    if ( isDefined( pkg.sfshop_dragonfire_configured ) )
    {
        return;
    }

    unit_ref = pkg.units[ 0 ];
    pkg.units = [];
    pkg.units[ 0 ] = unit_ref;
    pkg.units[ 1 ] = unit_ref;
    pkg.numunits = 2;
    // The automatic scheduler and the stock spawn guard both enforce this cap.
    pkg.max_friendly = level.sfmenu.max_allied_dragonfires;
    pkg.sfshop_dragonfire_configured = 1;
}

sfshop_configure_wave_infantry_package()
{
    pkg = maps\_so_rts_catalog::package_getpackagebytype( "infantry_enemy_reg2_pkg" );
    if ( !isDefined( pkg ) || !isDefined( pkg.units ) || pkg.units.size == 0 )
    {
        return;
    }
    if ( isDefined( pkg.sfshop_wave_infantry_configured ) )
    {
        return;
    }

    first_unit = pkg.units[ 0 ];
    second_unit = first_unit;
    if ( pkg.units.size > 1 )
    {
        second_unit = pkg.units[ 1 ];
    }
    pkg.units = [];
    pkg.units[ 0 ] = first_unit;
    pkg.units[ 1 ] = second_unit;
    pkg.numunits = 2;
    pkg.sfshop_wave_infantry_configured = 1;
}

// Cancel both the shared Strike Force clock (owned by the player) and the
// Drone defense clock (owned by level). Repeating this also catches a phase
// timer created after this script initializes.
sfshop_remove_time_limits()
{
    level endon( "rts_terminated" );
    level.rts.game_rules.time = 30000;

    while ( !common_scripts\utility::flag( "rts_start_clock" ) )
    {
        wait 0.1;
    }

    // Both this thread and the stock countdown wake from rts_start_clock. Send
    // cancellation repeatedly during the first two seconds to remove the race.
    i = 0;
    while ( i < 40 )
    {
        level.rts.game_rules.time = 30000;
        level.rts.player notify( "kill_countdown" );
        level notify( "kill_countdown" );
        maps\_so_rts_support::time_countdown_delete();
        wait 0.05;
        i++;
    }

    while ( 1 )
    {
        level.rts.game_rules.time = 30000;
        level.rts.player notify( "kill_countdown" );
        level notify( "kill_countdown" );
        maps\_so_rts_support::time_countdown_delete();
        wait 5;
    }
}

// Every Strike Force map routes its win/lose result through
// level.custom_mission_complete. Replacing that callback keeps this survival
// variant running instead of opening either the victory or defeat screen.
sfshop_endless_outcome_guard()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        if ( level.sfmenu.allow_mission_complete )
        {
            level.custom_mission_complete = level.sfmenu.original_mission_complete;
            return;
        }
        level.custom_mission_complete = ::sfshop_suppress_mission_complete;

        if ( common_scripts\utility::flag( "rts_game_over" ) )
        {
            common_scripts\utility::flag_clear( "rts_game_over" );
        }

        wait 0.1;
    }
}

sfshop_suppress_mission_complete( success, param )
{
    if ( !isDefined( level.sfmenu ) )
    {
        return;
    }

    level.rts.game_success = undefined;
    level.rts.game_rules.time = 30000;
    level.rts.player setclientdvar( "cg_aggressiveCullRadius", 100 );

    if ( isDefined( level.rts.player.hud_damagefeedback ) )
    {
        level.rts.player.hud_damagefeedback.alpha = 1;
    }

    if ( common_scripts\utility::flag( "rts_game_over" ) )
    {
        common_scripts\utility::flag_clear( "rts_game_over" );
    }

    if ( common_scripts\utility::flag( "block_input" ) )
    {
        common_scripts\utility::flag_clear( "block_input" );
    }

    level.rts.player freezecontrols( 0 );

    if ( isDefined( success ) && success )
    {
        level.rts.player iprintlnbold( "Mission completion suppressed - clear all five waves" );
    }
    else
    {
        level.rts.player iprintlnbold( "Defeat prevented - wave mode continues" );
    }
}

// The stock overhead/free-camera view enables client flags 3/4 and changes
// vc_lut to -3, producing its blue electronic-camera treatment. Keep the RTS
// controls and HUD active while continuously neutralizing only that filter.
sfshop_remove_freecam_filter()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        if ( common_scripts\utility::flag( "rts_mode" ) )
        {
            level.rts.player clearclientflag( 3 );
            level.rts.player clearclientflag( 4 );
            setsaveddvar( "vc_lut", 0 );
        }

        wait 0.05;
    }
}

// After one minute, keep all stock/free allied reinforcement quantities at
// zero. A shop purchase temporarily opens exactly one package for spawning.
sfshop_disable_free_reinforcements()
{
    level endon( "rts_terminated" );
    // This thread is started immediately after start_rts, so this is one
    // minute from RTS initialization even on maps with a delayed combat clock.
    wait 60;
    level.sfmenu.shop_lock_enabled = 1;

    while ( 1 )
    {
        if ( !level.sfmenu.purchase_in_progress )
        {
            sfshop_lock_allied_package( "infantry_ally_reg_pkg" );
            sfshop_lock_allied_package( "infantry_ally_reg2_pkg" );
            sfshop_lock_allied_package( "infantry_ally_reg3_pkg" );
            sfshop_lock_allied_package( "infantry_ally_reg4_pkg" );
            sfshop_lock_allied_package( "metalstorm_pkg" );
            sfshop_lock_allied_package( "bigdog_pkg" );
            sfshop_lock_allied_package( "turret_pkg" );
            sfshop_lock_allied_package( "quadrotor_pkg" );
        }
        wait 0.25;
    }
}

sfshop_lock_allied_package( package_name )
{
    pkg = maps\_so_rts_catalog::package_getpackagebytype( package_name );
    if ( isDefined( pkg ) )
    {
        pkg.qty[ "allies" ] = 0;
    }
}

// Send one normal cargo-VTOL containing the stock two-drone package every two
// minutes. If the entity reserve or an allied VTOL route is busy, retry shortly
// instead of losing that scheduled pair.
sfshop_automatic_dragonfire_reinforcements()
{
    level endon( "rts_terminated" );
    wait level.sfmenu.dragonfire_spawn_interval;

    while ( 1 )
    {
        while ( !sfshop_spawn_automatic_dragonfire_pair() )
        {
            wait 1;
        }
        wait level.sfmenu.dragonfire_spawn_interval;
    }
}

sfshop_spawn_automatic_dragonfire_pair()
{
    if ( level.sfmenu.purchase_in_progress || !isDefined( level.rts.allied_center ) )
    {
        return 0;
    }
    if ( sfshop_count_allied_dragonfires() + 2 > level.sfmenu.max_allied_dragonfires )
    {
        return 0;
    }

    // Preserve the same 300-slot safety reserve used by enemy wave spawning.
    if ( sfshop_refresh_entity_capacity() < level.sfmenu.spawn_pause_threshold + 6 )
    {
        return 0;
    }

    pkg = maps\_so_rts_catalog::package_getpackagebytype( "quadrotor_pkg" );
    if ( !isDefined( pkg ) )
    {
        return 0;
    }

    sfshop_ensure_transport_slots( "allies", "vtol", level.sfmenu.max_active_deliveries );
    if ( sfshop_count_active_deliveries( "allies" ) >= level.sfmenu.max_active_deliveries || !maps\_so_rts_catalog::istransportavailable( "allies", "vtol" ) )
    {
        return 0;
    }

    path_start = maps\_so_rts_support::chopper_closest_open_path_start( level.rts.allied_center.origin, "drop_path_start", "script_unload", "allies", "vtol" );
    if ( !isDefined( path_start ) )
    {
        return 0;
    }

    old_qty = pkg.qty[ "allies" ];
    old_delivery = pkg.delivery;
    old_cost = pkg.cost[ "allies" ];
    old_nextavail = pkg.nextavail[ "allies" ];

    // There are no waits between opening and restoring this shared package, so
    // enemy spawning cannot observe these temporary allied-delivery values.
    level.sfmenu.purchase_in_progress = 1;
    pkg.qty[ "allies" ] = -1;
    pkg.enforce_deps[ "allies" ] = 0;
    pkg.selectable = 1;
    pkg.nextavail[ "allies" ] = 0;
    pkg.cost[ "allies" ] = 0;
    pkg.max_friendly = level.sfmenu.max_allied_dragonfires;
    pkg.delivery = "CARGO_VTOL";

    squadid = maps\_so_rts_catalog::spawn_package( "quadrotor_pkg", "allies", 0, ::sfshop_register_automatic_dragonfire_squad );

    pkg.delivery = old_delivery;
    pkg.cost[ "allies" ] = old_cost;
    pkg.nextavail[ "allies" ] = old_nextavail;
    if ( level.sfmenu.shop_lock_enabled )
    {
        pkg.qty[ "allies" ] = 0;
    }
    else
    {
        pkg.qty[ "allies" ] = old_qty;
    }
    level.sfmenu.purchase_in_progress = 0;

    if ( !isDefined( squadid ) )
    {
        return 0;
    }

    if ( isDefined( level.rts.squads[ squadid ] ) )
    {
        level.rts.squads[ squadid ].sfshop_managed = 1;
        level.rts.squads[ squadid ].sfshop_automatic_dragonfire = 1;
    }
    return 1;
}

sfshop_count_allied_dragonfires()
{
    count = 0;
    vehicles = getvehiclearray( "allies" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) )
        {
            package_name = vehicles[ i ] sfshop_get_package_name();
            if ( isDefined( package_name ) && isSubStr( package_name, "quadrotor" ) )
            {
                count++;
            }
        }
        i++;
    }

    // Include drones assigned to a cargo VTOL but not spawned yet, preventing a
    // second scheduled pair from being queued while the first pair is in flight.
    if ( isDefined( level.rts.transport.vtol ) )
    {
        i = 0;
        while ( i < level.rts.transport.vtol.size )
        {
            transport = level.rts.transport.vtol[ i ];
            if ( isDefined( transport ) && isDefined( transport.team ) && transport.team == "allies" && ( transport.state == 1 || transport.state == 3 ) && isDefined( transport.pkg_ref ) && isDefined( transport.pkg_ref.ref ) && isSubStr( transport.pkg_ref.ref, "quadrotor" ) )
            {
                pending = transport.pkg_ref.units.size;
                if ( isDefined( transport.squadid ) && isDefined( level.rts.squads[ transport.squadid ] ) && isDefined( level.rts.squads[ transport.squadid ].members ) )
                {
                    pending -= level.rts.squads[ transport.squadid ].members.size;
                }
                if ( pending > 0 )
                {
                    count += pending;
                }
            }
            i++;
        }
    }
    return count;
}

sfshop_register_automatic_dragonfire_squad( squadid )
{
    if ( !isDefined( squadid ) || !isDefined( level.rts.squads[ squadid ] ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    if ( !isDefined( squad.pkg_ref ) || squad.pkg_ref.ref != "quadrotor_pkg" )
    {
        return;
    }

    squad.sfshop_managed = 1;
    squad.sfshop_automatic_dragonfire = 1;
    sfshop_mark_managed_squad_members( squadid );
    if ( !isDefined( squad.sfshop_dragonfire_tracking ) )
    {
        squad.sfshop_dragonfire_tracking = 1;
        squad.sfshop_dragonfire_expiry_started = 1;
        sfshop_dragonfire_issue_target( squadid );
        level thread sfshop_dragonfire_retarget( squadid );
        level thread sfshop_expire_allied_dragonfire_squad( squadid );
    }
}

// Polling catches stock units, custom-package units and units killed by either
// the human player or friendly AI without replacing the game's kill callbacks.
sfshop_entity_monitor()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        actors = getaiarray();
        i = 0;
        while ( i < actors.size )
        {
            actors[ i ] sfshop_register_entity();
            i++;
        }

        vehicles = getvehiclearray();
        i = 0;
        while ( i < vehicles.size )
        {
            vehicles[ i ] sfshop_register_entity();
            i++;
        }

        wait 0.2;
    }
}

// Long Strike Force sessions can leave an otherwise-live squad with a stale
// actor or vehicle path. Sample all mobile combat units in one level thread so
// the fix does not add a permanent watcher thread for every spawned entity.
sfshop_ai_freeze_watchdog()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        actors = getaiarray();
        i = 0;
        while ( i < actors.size )
        {
            if ( isDefined( actors[ i ] ) )
            {
                actors[ i ] sfshop_sample_ai_liveness();
            }
            i++;
        }

        vehicles = getvehiclearray();
        i = 0;
        while ( i < vehicles.size )
        {
            if ( isDefined( vehicles[ i ] ) )
            {
                vehicles[ i ] sfshop_sample_ai_liveness();
            }
            i++;
        }
        wait level.sfmenu.ai_watchdog_interval;
    }
}

sfshop_sample_ai_liveness()
{
    if ( !isDefined( self ) || !isalive( self ) || !isDefined( self.team ) || ( self.team != "allies" && self.team != "axis" ) || !isDefined( self.squadid ) || !isDefined( level.rts.squads[ self.squadid ] ) )
    {
        return;
    }

    package_name = self sfshop_get_package_name();
    if ( !isDefined( package_name ) || package_name == "turret_pkg" || isDefined( self.rts_unloaded ) && !self.rts_unloaded || isDefined( self.sfshop_prelanding_protected ) || self sfshop_is_player_controlled_ai() )
    {
        self.sfshop_ai_watch_origin = self.origin;
        self.sfshop_ai_still_time = 0;
        return;
    }

    if ( !isDefined( self.sfshop_ai_watch_origin ) )
    {
        self.sfshop_ai_watch_origin = self.origin;
        self.sfshop_ai_still_time = 0;
        return;
    }

    if ( distancesquared( self.origin, self.sfshop_ai_watch_origin ) >= 256 )
    {
        self.sfshop_ai_watch_origin = self.origin;
        self.sfshop_ai_still_time = 0;
        return;
    }

    if ( !isDefined( self.sfshop_ai_still_time ) )
    {
        self.sfshop_ai_still_time = 0;
    }
    self.sfshop_ai_still_time += level.sfmenu.ai_watchdog_interval;
    if ( self.sfshop_ai_still_time < level.sfmenu.ai_freeze_timeout )
    {
        return;
    }

    squad = level.rts.squads[ self.squadid ];
    if ( isDefined( squad.sfshop_last_ai_recovery ) && getTime() - squad.sfshop_last_ai_recovery < level.sfmenu.ai_recovery_cooldown )
    {
        self.sfshop_ai_watch_origin = self.origin;
        self.sfshop_ai_still_time = 0;
        return;
    }

    squad.sfshop_last_ai_recovery = getTime();
    sfshop_recover_frozen_squad( self.squadid );
}

sfshop_is_player_controlled_ai()
{
    if ( isDefined( self.playerinhabited ) && self.playerinhabited )
    {
        return 1;
    }
    if ( !isDefined( level.rts.player ) || !isDefined( level.rts.player.ally ) )
    {
        return 0;
    }
    if ( isDefined( level.rts.player.ally.vehicle ) && level.rts.player.ally.vehicle == self )
    {
        return 1;
    }
    return isDefined( level.rts.player.ally.swapai ) && level.rts.player.ally.swapai == self;
}

sfshop_recover_frozen_squad( squadid )
{
    if ( !isDefined( squadid ) || !isDefined( level.rts.squads[ squadid ] ) || !isDefined( level.rts.squads[ squadid ].members ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    members = squad.members;
    i = 0;
    while ( i < members.size )
    {
        unit = members[ i ];
        if ( isDefined( unit ) && isalive( unit ) && ( !isDefined( unit.rts_unloaded ) || unit.rts_unloaded ) && !isDefined( unit.sfshop_prelanding_protected ) && !unit sfshop_is_player_controlled_ai() )
        {
            // Release stale scripted holds left behind by an expired vanilla
            // movement state, then let the stock squad code rebuild the route.
            unit.fixednode = 0;
            unit.ignoreall = 0;
            unit.ignoreme = 0;
            if ( unit isvehicle() )
            {
                unit clearvehgoalpos();
                if ( issentient( unit ) )
                {
                    unit vehclearentitytarget();
                }
            }
            else
            {
                unit clearentitytarget();
            }
            unit.sfshop_ai_watch_origin = unit.origin;
            unit.sfshop_ai_still_time = 0;
        }
        i++;
    }

    maps\_so_rts_squad::reissuesquadlastorders( squadid );
    if ( isDefined( squad.pkg_ref ) && squad.pkg_ref.ref == "metalstorm_pkg" )
    {
        squad.sfshop_agr_target = undefined;
        sfshop_agr_issue_target( squadid );
    }
    else if ( isDefined( squad.pkg_ref ) && squad.pkg_ref.ref == "quadrotor_pkg" && isDefined( squad.members ) && squad.members.size > 0 && isDefined( squad.members[ 0 ].team ) && squad.members[ 0 ].team == "allies" )
    {
        squad.sfshop_dragonfire_target = undefined;
        sfshop_dragonfire_issue_target( squadid );
    }
}

// The Zombies-only dropped-weapon helper causes an SP runtime error. Scan the
// normal SP entity list instead and select only world pickup classnames. Held
// weapons are inventory data, not entities whose classname starts "weapon_".
sfshop_dropped_weapon_monitor()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        entities = getentarray();
        i = 0;
        while ( i < entities.size )
        {
            if ( isDefined( entities[ i ] ) && isDefined( entities[ i ].classname ) && isSubStr( entities[ i ].classname, "weapon_" ) && !isDefined( entities[ i ].sfshop_drop_cleanup_started ) )
            {
                entities[ i ].sfshop_drop_cleanup_started = 1;
                entities[ i ] thread sfshop_delete_dropped_weapon_after_delay();
            }
            i++;
        }
        wait 1;
    }
}

sfshop_delete_dropped_weapon_after_delay()
{
    self endon( "death" );
    level endon( "rts_terminated" );
    wait 60;

    if ( isDefined( self ) )
    {
        self delete();
    }
}

sfshop_register_entity()
{
    if ( !isDefined( self ) || !isDefined( self.team ) )
    {
        return;
    }

    package_name = self sfshop_get_package_name();
    if ( !isDefined( package_name ) )
    {
        return;
    }

    if ( isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].sfshop_managed ) )
    {
        self.sfshop_managed = 1;
        if ( !isDefined( self.sfshop_cleanup_started ) )
        {
            self.sfshop_cleanup_started = 1;
            self thread sfshop_cleanup_managed_entity();
        }
    }

    // ai_initialize marks combat units initialized. Sentries are map-created
    // vehicles and do not always receive that marker.
    ready = 0;
    if ( isDefined( self.initialized ) && self.initialized )
    {
        ready = 1;
    }
    else if ( package_name == "turret_pkg" && isDefined( self.health ) )
    {
        ready = 1;
    }

    if ( ready && !isDefined( self.sfshop_health_boosted ) )
    {
        self.sfshop_health_boosted = 1;
        is_claw = 0;
        if ( package_name == "bigdog_pkg" )
        {
            is_claw = 1;
        }
        if ( isDefined( self.isbigdog ) && self.isbigdog )
        {
            is_claw = 1;
        }

        is_enemy_soldier = self.team == "axis" && isSubStr( package_name, "infantry_" );
        is_enemy_dragonfire = self.team == "axis" && isSubStr( package_name, "quadrotor" );
        is_enemy_claw = self.team == "axis" && is_claw;

        if ( is_enemy_dragonfire && isDefined( self.health ) && self.health > 0 )
        {
            // Ten is the requested low-but-survivable Dragonfire health value.
            self.health = 10;
            self.health_max = 10;
            self.maxhealth = 10;
        }
        else if ( is_enemy_soldier )
        {
            self sfshop_multiply_health( 2 );
        }
        else if ( is_enemy_claw )
        {
            self sfshop_multiply_health( 3 );
        }
        else if ( !is_enemy_soldier && !is_claw && isDefined( self.health ) && self.health > 0 )
        {
            self sfshop_multiply_health( 5 );
        }
    }

    if ( ready && ( package_name == "bigdog_pkg" || isDefined( self.isbigdog ) && self.isbigdog ) && !isDefined( self.sfshop_claw_scale_started ) )
    {
        self.sfshop_claw_scale_started = 1;
        self thread sfshop_scale_claw_after_deployment();
    }

    if ( ready && self.team == "axis" && ( package_name == "bigdog_pkg" || isDefined( self.isbigdog ) && self.isbigdog ) )
    {
        self.sfshop_enemy_claw_unstoppable = 1;
        if ( !isDefined( self.sfshop_claw_resistance_started ) )
        {
            self.sfshop_claw_resistance_started = 1;
            self thread sfshop_enemy_claw_resistance_watch();
        }
    }

    if ( ready && !isDefined( self.sfshop_damage_override_installed ) )
    {
        self.sfshop_damage_override_installed = 1;
        if ( self isvehicle() )
        {
            self.sfshop_vehicle_damage_override_orig = self.overridevehicledamage;
            self.overridevehicledamage = ::sfshop_vehicle_damage_override;
        }
        else
        {
            self.sfshop_actor_damage_override_orig = self.overrideactordamage;
            self.overrideactordamage = ::sfshop_actor_damage_override;
        }
    }

    if ( ready && self.team == "allies" && ( package_name == "bigdog_pkg" || isDefined( self.isbigdog ) && self.isbigdog ) )
    {
        // Mark both the C.L.A.W. and its turret so either entity can be reported
        // as the attacker by the engine's vehicle damage callback.
        self.sfshop_claw_minigun_source = 1;
        if ( isDefined( self.turret ) )
        {
            self.turret.sfshop_claw_minigun_source = 1;
            self.turret.sfshop_claw_owner = self;
        }
    }

    if ( ready && self.team == "allies" && level.sfmenu.juggernog )
    {
        self sfshop_apply_juggernog();
    }

    if ( ready && self.team == "allies" && isSubStr( package_name, "infantry_" ) && !isDefined( self.sfshop_wander_watch_started ) )
    {
        self.sfshop_wander_watch_started = 1;
        self thread sfshop_allied_soldier_movement_watch();
    }

    if ( ready && isSubStr( package_name, "infantry_" ) && !isDefined( self.sfshop_long_range_watch_started ) )
    {
        self.sfshop_long_range_watch_started = 1;
        self thread sfshop_soldier_long_range_watch();
    }

    if ( ready && self.team == "allies" && isSubStr( package_name, "quadrotor" ) && self isvehicle() && !isDefined( self.sfshop_slow_dragonfire_started ) )
    {
        self.sfshop_slow_dragonfire_started = 1;
        self thread sfshop_slow_allied_dragonfire();
    }

    if ( ready && package_name == "metalstorm_pkg" && self isvehicle() && !isDefined( self.sfshop_fast_agr_started ) )
    {
        self.sfshop_fast_agr_started = 1;
        self thread sfshop_speed_up_agr();
    }

    // Death tracking does not depend on the stock initialized flag. Attaching it
    // as soon as the squad/package exists closes the fast-kill reward race.
    if ( self.team == "axis" && !isDefined( self.sfshop_reward_tracked ) )
    {
        self.sfshop_reward_tracked = 1;
        self thread sfshop_reward_enemy_death( package_name );
    }

    if ( ready && self.team == "axis" && isDefined( self.sfshop_managed ) && isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].sfshop_enemy_wave ) && !isDefined( self.sfshop_stuck_watch_started ) )
    {
        self.sfshop_stuck_watch_started = 1;
        self thread sfshop_enemy_stuck_watch();
    }
}

sfshop_scale_claw_after_deployment()
{
    level endon( "rts_terminated" );
    self endon( "death" );

    // Scaling while linked to the cargo rig can break its drop animation. Wait
    // until the stock delivery has released the C.L.A.W. onto the ground.
    while ( isalive( self ) && ( !isDefined( self.rts_unloaded ) || !self.rts_unloaded || isDefined( self.ignoreme ) && self.ignoreme ) )
    {
        wait 0.1;
    }
    if ( isalive( self ) )
    {
        self setscale( 2 );
    }
}

sfshop_accelerate_delivery_transports()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        if ( isDefined( level.rts.transport ) )
        {
            if ( isDefined( level.rts.transport.helo ) )
            {
                sfshop_accelerate_transport_load_slots( level.rts.transport.helo );
            }
            if ( isDefined( level.rts.transport.vtol ) )
            {
                sfshop_accelerate_transport_load_slots( level.rts.transport.vtol );
            }
        }

        aircraft = getentarray( "transport", "script_noteworthy" );
        i = 0;
        while ( i < aircraft.size )
        {
            if ( isDefined( aircraft[ i ] ) && !isDefined( aircraft[ i ].sfshop_speed_doubled ) )
            {
                aircraft[ i ].sfshop_speed_doubled = 1;
                if ( isDefined( aircraft[ i ].speed ) && aircraft[ i ].speed > 0 )
                {
                    aircraft[ i ].speed *= 2;
                    aircraft[ i ] vehicle_setspeed( aircraft[ i ].speed, 60, "sfshop double transport speed" );
                }
                // This also accelerates VTOL door/airframe deployment animations.
                aircraft[ i ].animplaybackrate = 2;
            }
            i++;
        }
        wait 0.05;
    }
}

sfshop_accelerate_transport_load_slots( slots )
{
    i = 0;
    while ( i < slots.size )
    {
        unit = slots[ i ];
        if ( unit.state == 3 && !isDefined( unit.sfshop_load_time_halved ) )
        {
            unit.sfshop_load_time_halved = 1;
            remaining = unit.loadtime - getTime();
            if ( remaining > 0 )
            {
                unit.loadtime = getTime() + int( remaining * 0.5 );
            }
        }
        else if ( unit.state == 0 )
        {
            unit.sfshop_load_time_halved = undefined;
        }
        i++;
    }
}

sfshop_slow_allied_dragonfire()
{
    level endon( "rts_terminated" );
    self endon( "death" );

    while ( isalive( self ) )
    {
        if ( !isDefined( self.rts_unloaded ) || self.rts_unloaded )
        {
            max_speed = level.sfmenu.allied_dragonfire_max_speed;
            if ( isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].sfshop_dragonfire_target ) && isalive( level.rts.squads[ self.squadid ].sfshop_dragonfire_target ) )
            {
                max_speed = level.sfmenu.allied_dragonfire_aggro_max_speed;
            }

            // The autonomous Dragonfire normally moves at roughly 30. Cruise at
            // one third speed and use the stronger one-fifth cap during aggro.
            self.vmaxspeedoverridge = max_speed;
            self.vmaxaispeedoverridge = max_speed;
            self setvehmaxspeed( max_speed );
        }
        wait 0.25;
    }
}

sfshop_speed_up_agr()
{
    level endon( "rts_terminated" );
    self endon( "death" );

    while ( isalive( self ) )
    {
        if ( !isDefined( self.rts_unloaded ) || self.rts_unloaded )
        {
            // Reapply the two-times overrides because stock vehicle orders can
            // rewrite speed limits when an A.G.R. receives a new path or target.
            self.vmaxspeedoverridge = level.sfmenu.agr_max_speed;
            self.vmaxaispeedoverridge = level.sfmenu.agr_ai_max_speed;
            self setvehmaxspeed( level.sfmenu.agr_max_speed );
        }
        wait 0.25;
    }
}

sfshop_multiply_health( multiplier )
{
    if ( !isDefined( self.health ) || self.health <= 0 )
    {
        return;
    }

    self.health = int( self.health * multiplier );
    if ( isDefined( self.health_max ) )
    {
        self.health_max = int( self.health_max * multiplier );
    }
    else
    {
        self.health_max = self.health;
    }
    if ( isDefined( self.maxhealth ) )
    {
        self.maxhealth = int( self.maxhealth * multiplier );
    }
    else
    {
        self.maxhealth = self.health_max;
    }
}

sfshop_enemy_claw_resistance_watch()
{
    level endon( "rts_terminated" );
    self endon( "death" );

    while ( isalive( self ) )
    {
        // Bigdog/C.L.A.W. is an AI actor. Suppress pain reactions and repeatedly
        // clear the generic flash/stun state used by tactical equipment.
        if ( isai( self ) && isDefined( self.a ) )
        {
            // Inline the stock disable_react helper. Calling it by name from an
            // injected root script produces an unresolved-external loader error.
            self.a.disablereact = 1;
        }
        self.allowreact = 0;
        self.flashendtime = 0;
        self notify( "not_stunned" );
        self clearclientflag( 9 );
        if ( isDefined( self.turret ) )
        {
            self.turret clearclientflag( 9 );
        }
        wait 0.1;
    }
}

sfshop_allied_soldier_movement_watch()
{
    level endon( "rts_terminated" );
    self endon( "death" );
    last_origin = self.origin;
    still_time = 0;

    while ( isalive( self ) )
    {
        wait 5;
        if ( distancesquared( self.origin, last_origin ) < 1024 )
        {
            still_time += 5;
        }
        else
        {
            still_time = 0;
            last_origin = self.origin;
        }

        if ( still_time < level.sfmenu.ally_stuck_timeout )
        {
            continue;
        }

        target = sfshop_find_closest_enemy( self.origin );
        if ( isDefined( target ) )
        {
            // A soldier holding a firing position is not frozen. Refresh the
            // distant target without ordering a close-range rush to its origin.
            self setentitytarget( target );
        }
        else
        {
            self.goalradius = 128;
            offset = sfshop_soldier_wander_offset( randomint( 8 ) );
            self setgoalpos( self.origin + offset );
        }
        still_time = 0;
        last_origin = self.origin;
    }
}

sfshop_soldier_long_range_watch()
{
    level endon( "rts_terminated" );
    self endon( "death" );
    // Remove only player-to-actor collision. The soldier remains solid to the
    // world and keeps its normal hit detection, damage callbacks and navigation.
    self setplayercollision( 0 );

    while ( isalive( self ) )
    {
        // Stock Strike Force infantry sees 1024 units away and only stops to
        // fight within 256 units while pathing. A 4096-unit envelope lets both
        // teams acquire and fire on distant targets instead of running at them.
        self.highlyawareradius = level.sfmenu.soldier_attack_distance;
        self.pathenemyfightdist = level.sfmenu.soldier_attack_distance;
        self.maxvisibledist = level.sfmenu.soldier_attack_distance;
        self.maxsightdistsqrd = level.sfmenu.soldier_attack_distance * level.sfmenu.soldier_attack_distance;
        self.canflank = 0;
        self.dontmelee = 1;
        wait 0.5;
    }
}

sfshop_soldier_wander_offset( index )
{
    if ( index == 0 )
    {
        return ( 480, 0, 0 );
    }
    if ( index == 1 )
    {
        return ( -480, 0, 0 );
    }
    if ( index == 2 )
    {
        return ( 0, 480, 0 );
    }
    if ( index == 3 )
    {
        return ( 0, -480, 0 );
    }
    if ( index == 4 )
    {
        return ( 340, 340, 0 );
    }
    if ( index == 5 )
    {
        return ( -340, 340, 0 );
    }
    if ( index == 6 )
    {
        return ( 340, -340, 0 );
    }
    return ( -340, -340, 0 );
}

sfshop_enemy_stuck_watch()
{
    level endon( "rts_terminated" );
    self endon( "death" );
    last_origin = self.origin;
    still_time = 0;
    recovery_attempted = 0;

    while ( isalive( self ) )
    {
        wait 5;
        if ( isDefined( self.sfshop_prelanding_protected ) )
        {
            last_origin = self.origin;
            still_time = 0;
            continue;
        }
        if ( isDefined( self.enemy ) && isalive( self.enemy ) )
        {
            // Long-range soldiers are allowed to hold a firing position.
            last_origin = self.origin;
            still_time = 0;
            recovery_attempted = 0;
            continue;
        }

        if ( distancesquared( self.origin, last_origin ) < 1024 )
        {
            still_time += 5;
        }
        else
        {
            still_time = 0;
            last_origin = self.origin;
            recovery_attempted = 0;
        }

        if ( still_time >= level.sfmenu.enemy_stuck_timeout )
        {
            if ( !recovery_attempted && isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) )
            {
                recovery_attempted = 1;
                still_time = 0;
                last_origin = self.origin;
                sfshop_recover_frozen_squad( self.squadid );
                continue;
            }

            // Keep the prior wave-softlock fallback only after a full recovery
            // attempt also failed for another complete timeout.
            self.sfshop_killed_for_stall = 1;
            self kill();
            return;
        }
    }
}

sfshop_apply_juggernog_to_all_allies()
{
    actors = getaiarray( "allies" );
    i = 0;
    while ( i < actors.size )
    {
        if ( isDefined( actors[ i ] ) )
        {
            actors[ i ] sfshop_apply_juggernog();
        }
        i++;
    }

    vehicles = getvehiclearray( "allies" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) )
        {
            vehicles[ i ] sfshop_apply_juggernog();
        }
        i++;
    }
}

sfshop_apply_juggernog()
{
    if ( isDefined( self.sfshop_juggernog_boosted ) || !isDefined( self.health ) || self.health <= 0 )
    {
        return;
    }

    self.sfshop_juggernog_boosted = 1;
    self.health = int( self.health * 2.5 );
    if ( isDefined( self.health_max ) )
    {
        self.health_max = int( self.health_max * 2.5 );
    }
    else
    {
        self.health_max = self.health;
    }
    if ( isDefined( self.maxhealth ) )
    {
        self.maxhealth = int( self.maxhealth * 2.5 );
    }
    else
    {
        self.maxhealth = self.health_max;
    }
}

sfshop_actor_damage_override( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, modelindex, psoffsettime, bonename )
{
    if ( self sfshop_is_allied_death_barrier_damage( eattacker, idamage ) )
    {
        self sfshop_begin_boundary_redeployment();
        return 0;
    }
    if ( isDefined( self.sfshop_prelanding_protected ) )
    {
        return 0;
    }
    if ( isDefined( self.sfshop_enemy_claw_unstoppable ) && sfshop_is_stun_attack( smeansofdeath, sweapon ) )
    {
        return 0;
    }

    if ( self.team == "axis" )
    {
        idamage = sfshop_scale_allied_claw_minigun_damage( einflictor, eattacker, idamage, smeansofdeath, sweapon );
    }
    if ( self.team == "axis" && level.sfmenu.double_tap && sfshop_is_allied_attacker( eattacker ) )
    {
        idamage = int( idamage * 2 );
    }

    package_name = self sfshop_get_package_name();
    block_headshot = isDefined( package_name ) && isSubStr( package_name, "infantry_" ) && sfshop_is_head_hit( shitloc, bonename );
    if ( block_headshot )
    {
        idamage = 0;
    }
    if ( isDefined( self.sfshop_actor_damage_override_orig ) )
    {
        idamage = [[ self.sfshop_actor_damage_override_orig ]]( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, modelindex, psoffsettime, bonename );
    }
    if ( block_headshot )
    {
        idamage = 0;
    }
    return idamage;
}

sfshop_vehicle_damage_override( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, psoffsettime, damagefromunderneath, modelindex, partname )
{
    if ( self sfshop_is_allied_death_barrier_damage( eattacker, idamage ) )
    {
        self sfshop_begin_boundary_redeployment();
        return 0;
    }
    if ( isDefined( self.sfshop_enemy_claw_unstoppable ) && sfshop_is_stun_attack( smeansofdeath, sweapon ) )
    {
        return 0;
    }
    if ( self.team == "axis" )
    {
        idamage = sfshop_scale_allied_claw_minigun_damage( einflictor, eattacker, idamage, smeansofdeath, sweapon );
    }
    if ( self.team == "axis" && level.sfmenu.double_tap && sfshop_is_allied_attacker( eattacker ) )
    {
        idamage = int( idamage * 2 );
    }
    if ( isDefined( self.sfshop_vehicle_damage_override_orig ) )
    {
        idamage = [[ self.sfshop_vehicle_damage_override_orig ]]( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, psoffsettime, damagefromunderneath, modelindex, partname );
    }
    return idamage;
}

sfshop_is_allied_death_barrier_damage( attacker, damage )
{
    if ( !isDefined( self.team ) || self.team != "allies" || isDefined( attacker ) || !isDefined( self.health ) || !isDefined( self.maxhealth ) )
    {
        return 0;
    }
    if ( damage < self.maxhealth || isDefined( self.sfshop_boundary_redeploy_pending ) )
    {
        return 0;
    }

    boundary = maps\_so_rts_support::clamporigintomapboundary( self.origin );
    return isDefined( boundary ) && !boundary.inbounds;
}

sfshop_begin_boundary_redeployment()
{
    if ( isDefined( self.sfshop_boundary_redeploy_pending ) )
    {
        return;
    }
    self.sfshop_boundary_redeploy_pending = 1;
    self thread sfshop_redeploy_ally_inside_boundary();
}

sfshop_redeploy_ally_inside_boundary()
{
    level endon( "rts_terminated" );
    self endon( "death" );

    boundary = maps\_so_rts_support::clamporigintomapboundary( self.origin );
    if ( !isDefined( boundary ) || boundary.inbounds )
    {
        self.sfshop_boundary_redeploy_pending = undefined;
        return;
    }

    redeploy_origin = boundary.origin;
    if ( isDefined( level.rts.bounds ) )
    {
        x = redeploy_origin[ 0 ];
        y = redeploy_origin[ 1 ];
        z = redeploy_origin[ 2 ];
        if ( x <= level.rts.bounds.ulx )
        {
            x = level.rts.bounds.ulx + 96;
        }
        else if ( x >= level.rts.bounds.lrx )
        {
            x = level.rts.bounds.lrx - 96;
        }
        if ( y <= level.rts.bounds.uly )
        {
            y = level.rts.bounds.uly + 96;
        }
        else if ( y >= level.rts.bounds.lry )
        {
            y = level.rts.bounds.lry - 96;
        }
        if ( z <= level.rts.bounds.minz )
        {
            z = level.rts.bounds.minz + 48;
        }
        else if ( z >= level.rts.bounds.maxz )
        {
            z = level.rts.bounds.maxz - 48;
        }
        redeploy_origin = ( x, y, z );
    }

    if ( isDefined( self.classname ) && self.classname == "script_model" )
    {
        self.origin = redeploy_origin;
    }
    else
    {
        self forceteleport( redeploy_origin, self.angles );
    }

    if ( isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) )
    {
        maps\_so_rts_squad::reissuesquadlastorders( self.squadid );
    }
    self.sfshop_boundary_redeploy_pending = undefined;
}

sfshop_is_stun_attack( means_of_death, weapon )
{
    if ( isDefined( weapon ) && ( isSubStr( weapon, "emp" ) || isSubStr( weapon, "stun" ) || isSubStr( weapon, "concussion" ) || isSubStr( weapon, "flash" ) || isSubStr( weapon, "shock" ) ) )
    {
        return 1;
    }
    if ( isDefined( means_of_death ) && ( isSubStr( means_of_death, "EMP" ) || isSubStr( means_of_death, "STUN" ) || isSubStr( means_of_death, "CONCUSSION" ) || isSubStr( means_of_death, "FLASH" ) || isSubStr( means_of_death, "SHOCK" ) ) )
    {
        return 1;
    }
    return 0;
}

sfshop_scale_allied_claw_minigun_damage( inflictor, attacker, damage, means_of_death, weapon )
{
    if ( damage <= 0 )
    {
        return damage;
    }
    if ( !sfshop_is_allied_claw_damage_source( attacker ) && !sfshop_is_allied_claw_damage_source( inflictor ) )
    {
        return damage;
    }

    // C.L.A.W. rockets/explosions keep their normal damage. The turret weapon
    // can arrive by name or only as a bullet means-of-death depending on whether
    // the C.L.A.W. is AI-controlled or currently controlled by the player.
    is_minigun = 0;
    if ( isDefined( weapon ) && ( isSubStr( weapon, "bigdog" ) || isSubStr( weapon, "minigun" ) ) )
    {
        is_minigun = 1;
    }
    else if ( isDefined( means_of_death ) && ( isSubStr( means_of_death, "bullet" ) || isSubStr( means_of_death, "BULLET" ) ) )
    {
        is_minigun = 1;
    }
    if ( !is_minigun )
    {
        return damage;
    }

    scaled_damage = int( damage * level.sfmenu.allied_claw_minigun_scale );
    if ( scaled_damage < 1 )
    {
        scaled_damage = 1;
    }
    return scaled_damage;
}

sfshop_is_allied_claw_damage_source( source )
{
    if ( !isDefined( source ) )
    {
        return 0;
    }

    // When the player takes over a C.L.A.W., the player can be reported as the
    // attacker while viewlockedentity remains the actual allied vehicle.
    if ( source == level.rts.player )
    {
        if ( !isDefined( source.viewlockedentity ) )
        {
            return 0;
        }
        source = source.viewlockedentity;
    }

    if ( isDefined( source.sfshop_claw_minigun_source ) )
    {
        return 1;
    }
    if ( isDefined( source.sfshop_claw_owner ) && isDefined( source.sfshop_claw_owner.team ) && source.sfshop_claw_owner.team == "allies" )
    {
        return 1;
    }

    package_name = source sfshop_get_package_name();
    return isDefined( source.team ) && source.team == "allies" && isDefined( package_name ) && package_name == "bigdog_pkg";
}

sfshop_is_allied_attacker( attacker )
{
    if ( !isDefined( attacker ) )
    {
        return 0;
    }
    if ( attacker == level.rts.player )
    {
        return 1;
    }
    return isDefined( attacker.team ) && attacker.team == "allies";
}

sfshop_is_head_hit( hit_location, bone_name )
{
    if ( isDefined( hit_location ) && ( isSubStr( hit_location, "head" ) || isSubStr( hit_location, "helmet" ) || isSubStr( hit_location, "neck" ) ) )
    {
        return 1;
    }
    if ( isDefined( bone_name ) && ( isSubStr( bone_name, "head" ) || isSubStr( bone_name, "helmet" ) || isSubStr( bone_name, "neck" ) ) )
    {
        return 1;
    }
    return 0;
}

// Only entities belonging to a squad created by this script are cleaned up.
// This preserves map objectives, stock AI and stock vehicles.
sfshop_cleanup_managed_entity()
{
    was_vehicle = self isvehicle();
    self waittill( "death" );

    if ( was_vehicle )
    {
        // Leave the wreck visible long enough for its stock death effect, then
        // release the entity if the vehicle is still destroyed.
        wait 8;
    }
    else
    {
        // Keep the short death animation, then free the corpse entity slot.
        wait 3;
    }

    if ( isDefined( self ) && !isalive( self ) )
    {
        self delete();
    }
}

sfshop_get_package_name()
{
    if ( isDefined( self.pkg_ref ) && isDefined( self.pkg_ref.ref ) )
    {
        return self.pkg_ref.ref;
    }

    if ( isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].pkg_ref ) )
    {
        return level.rts.squads[ self.squadid ].pkg_ref.ref;
    }

    return undefined;
}

sfshop_reward_enemy_death( package_name )
{
    is_wave5_agr = 0;
    is_wave5_claw = 0;
    if ( package_name == "metalstorm_pkg" && isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].sfshop_wave_number ) && level.rts.squads[ self.squadid ].sfshop_wave_number == 5 )
    {
        is_wave5_agr = 1;
    }
    if ( package_name == "bigdog_pkg" && isDefined( self.squadid ) && isDefined( level.rts.squads[ self.squadid ] ) && isDefined( level.rts.squads[ self.squadid ].sfshop_wave_number ) && level.rts.squads[ self.squadid ].sfshop_wave_number == 5 )
    {
        is_wave5_claw = 1;
    }
    self waittill( "death" );

    if ( !isDefined( level.sfmenu ) )
    {
        return;
    }

    reward = 100;
    if ( isSubStr( package_name, "quadrotor" ) )
    {
        reward = 50;
    }
    else if ( isSubStr( package_name, "bigdog" ) )
    {
        reward = 300;
    }
    else if ( isSubStr( package_name, "metalstorm" ) )
    {
        reward = 200;
    }

    if ( is_wave5_agr )
    {
        level.sfmenu.wave5_agrs_killed++;
    }
    if ( is_wave5_claw )
    {
        level.sfmenu.wave5_claws_killed++;
    }

    sfshop_queue_reward( reward );
}

sfshop_queue_reward( reward )
{
    if ( !isDefined( level.sfmenu ) || !isDefined( level.sfmenu.reward_queue ) || reward <= 0 )
    {
        return;
    }
    level.sfmenu.reward_queue[ level.sfmenu.reward_queue.size ] = reward;
}

// A single writer commits all death rewards. This prevents two same-frame
// death threads from reading the same old balance and losing one of the kills.
sfshop_reward_processor()
{
    level endon( "rts_terminated" );
    while ( 1 )
    {
        wait 0.05;
        if ( !isDefined( level.sfmenu.reward_queue ) || level.sfmenu.reward_queue.size == 0 )
        {
            continue;
        }

        rewards = level.sfmenu.reward_queue;
        level.sfmenu.reward_queue = [];
        total_reward = 0;
        i = 0;
        while ( i < rewards.size )
        {
            total_reward += rewards[ i ];
            i++;
        }

        if ( total_reward > 0 )
        {
            level.sfmenu.points += total_reward;
            sfshop_update_points_hud();
            level.rts.player iprintln( "+" + total_reward + " shop points" );
        }
    }
}

sfshop_create_points_hud()
{
    level.sfmenu.wallet = newhudelem();
    level.sfmenu.wallet.horzalign = "left";
    level.sfmenu.wallet.vertalign = "top";
    level.sfmenu.wallet.alignx = "left";
    level.sfmenu.wallet.aligny = "top";
    level.sfmenu.wallet.x = 18;
    level.sfmenu.wallet.y = 52;
    level.sfmenu.wallet.fontscale = 1.35;
    level.sfmenu.wallet.foreground = 1;
    level.sfmenu.wallet.sort = 15;
    level.sfmenu.wallet.alpha = 1;
    level.sfmenu.wallet.color = ( 1, 0.65, 0.15 );
    level.sfmenu.wallet.hidewheninmenu = 1;
    sfshop_update_points_hud();
}

sfshop_update_points_hud()
{
    if ( isDefined( level.sfmenu.wallet ) )
    {
        level.sfmenu.wallet settext( "SHOP POINTS: " + level.sfmenu.points );
    }
    if ( isDefined( level.sfmenu.balance ) )
    {
        level.sfmenu.balance settext( "AVAILABLE POINTS: " + level.sfmenu.points );
    }
}

sfshop_entity_capacity_monitor()
{
    level endon( "rts_terminated" );

    while ( 1 )
    {
        free_entities = sfshop_refresh_entity_capacity();

        if ( free_entities < level.sfmenu.purchase_block_threshold )
        {
            if ( !level.sfmenu.entity_warning_shown )
            {
                level.sfmenu.entity_warning_shown = 1;
                level.rts.player iprintlnbold( "ENTITY LIMIT CRITICAL - spawning paused and shop locked" );
            }
        }
        else if ( free_entities < level.sfmenu.spawn_pause_threshold )
        {
            if ( !level.sfmenu.entity_warning_shown )
            {
                level.sfmenu.entity_warning_shown = 1;
                level.rts.player iprintlnbold( "ENTITY BUFFER LOW - enemy spawning paused" );
            }
        }
        else if ( free_entities >= level.sfmenu.spawn_pause_threshold )
        {
            level.sfmenu.entity_warning_shown = 0;
        }

        wait 0.25;
    }
}

sfshop_refresh_entity_capacity()
{
    entities = getentarray();
    free_entities = level.sfmenu.entity_limit - entities.size;

    if ( free_entities < 0 )
    {
        free_entities = 0;
    }

    level.sfmenu.free_entities = free_entities;

    return free_entities;
}

sfshop_has_safe_entity_capacity()
{
    return sfshop_has_purchase_capacity();
}

sfshop_has_enemy_spawn_capacity()
{
    return sfshop_refresh_entity_capacity() >= level.sfmenu.spawn_pause_threshold;
}

sfshop_has_purchase_capacity()
{
    return sfshop_refresh_entity_capacity() >= level.sfmenu.purchase_block_threshold;
}

// Five finite waves replace the stock timed defense. There is no active-enemy
// cap. The five-aircraft delivery limit and free-slot
// reserve stagger only transports; they do not limit the living enemy total.
// Wave 1 has a 30-second opening countdown. Later waves have a ten-second
// HUD-only break without restoring the white "Wave incoming" announcement.
sfshop_enemy_spawn_controller()
{
    level endon( "rts_terminated" );

    while ( !common_scripts\utility::flag( "start_rts_enemy" ) )
    {
        wait 0.2;
    }

    // Stop the stock package director; this script is the only wave authority.
    level notify( "end_enemy_player" );
    sfshop_ensure_transport_slots( "axis", "helo", level.sfmenu.max_active_deliveries );
    sfshop_ensure_transport_slots( "axis", "vtol", level.sfmenu.max_active_deliveries );
    sfshop_create_wave_hud();

    wave = 1;
    while ( wave <= 5 )
    {
        level.sfmenu.wave_number = wave;
        if ( wave == 1 )
        {
            sfshop_wave_intermission( wave, 30, 1 );
        }
        else
        {
            sfshop_wave_intermission( wave, 10, 0 );
        }
        sfshop_set_wave_quota( wave );

        while ( 1 )
        {
            sfshop_prepare_enemy_packages();
            spawned = 0;
            if ( sfshop_has_enemy_spawn_capacity() )
            {
                spawned = sfshop_fill_wave_quota();
            }

            // Only entities tagged for this wave decide whether it has cleared.
            // Stock/map axis entities must not hold the wave controller open.
            active_total = sfshop_count_active_wave_enemies( wave );
            pending_total = sfshop_count_pending_wave_units( wave );
            if ( wave == 5 )
            {
                if ( level.sfmenu.wave5_claws_unlocked )
                {
                    sfshop_update_wave_hud( "WAVE 5  ENEMIES: " + ( active_total + pending_total ) + "  CLAWS: " + level.sfmenu.wave5_claws_killed + "/" + level.sfmenu.wave5_claw_total );
                }
                else
                {
                    sfshop_update_wave_hud( "WAVE 5  ENEMIES: " + ( active_total + pending_total ) + "  A.G.R.S: " + level.sfmenu.wave5_agrs_killed + "/5" );
                }
            }
            else
            {
                sfshop_update_wave_hud( "WAVE " + wave + "  ENEMIES: " + ( active_total + pending_total ) );
            }

            if ( sfshop_wave_quota_empty() && active_total == 0 && pending_total == 0 )
            {
                if ( wave < 5 || level.sfmenu.wave5_claws_killed >= level.sfmenu.wave5_claw_total )
                {
                    break;
                }
            }
            wait 1;
        }

        if ( wave == 5 )
        {
            sfshop_finish_wave_mode();
            return;
        }

        level.rts.player iprintlnbold( "Wave " + wave + " cleared!" );
        wave++;
    }
}

sfshop_prepare_enemy_packages()
{
    sfshop_make_enemy_package_infinite( "infantry_enemy_reg_pkg" );
    sfshop_make_enemy_package_infinite( "infantry_enemy_reg2_pkg" );
    sfshop_make_enemy_package_infinite( "infantry_enemy_elite_pkg" );
    sfshop_make_enemy_package_infinite( "infantry_afghan_rpg_pkg" );
    sfshop_make_enemy_package_infinite( "infantry_enemy_ied_pkg" );
    sfshop_make_enemy_package_infinite( "quadrotor_pkg" );
    sfshop_make_enemy_package_infinite( "metalstorm_pkg" );
    sfshop_make_enemy_package_infinite( "bigdog_pkg" );
}

sfshop_set_wave_quota( wave )
{
    level.sfmenu.wave_soldiers_remaining = 0;
    level.sfmenu.wave_dragonfires_remaining = 0;
    level.sfmenu.wave_agrs_remaining = 0;
    level.sfmenu.wave_claws_remaining = 0;

    if ( wave == 1 )
    {
        level.sfmenu.wave_soldiers_remaining = sfshop_scale_enemy_spawn_count( 12 );
    }
    else if ( wave == 2 )
    {
        level.sfmenu.wave_soldiers_remaining = sfshop_scale_enemy_spawn_count( 10 );
        level.sfmenu.wave_agrs_remaining = sfshop_scale_enemy_spawn_count( 1 );
    }
    else if ( wave == 3 )
    {
        level.sfmenu.wave_soldiers_remaining = sfshop_scale_enemy_spawn_count( 16 );
        level.sfmenu.wave_agrs_remaining = sfshop_scale_enemy_spawn_count( 2 );
    }
    else if ( wave == 4 )
    {
        level.sfmenu.wave_soldiers_remaining = sfshop_scale_enemy_spawn_count( 20 );
        level.sfmenu.wave_agrs_remaining = sfshop_scale_enemy_spawn_count( 3 );
        level.sfmenu.wave_claws_remaining = sfshop_scale_enemy_spawn_count( 1 );
    }
    else if ( wave == 5 )
    {
        level.sfmenu.wave_soldiers_remaining = sfshop_scale_enemy_spawn_count( 32 );
        level.sfmenu.wave_agrs_remaining = sfshop_scale_enemy_spawn_count( 5 );
        level.sfmenu.wave_claws_remaining = sfshop_scale_enemy_spawn_count( 3 );
        level.sfmenu.wave5_claw_total = level.sfmenu.wave_claws_remaining;
        level.sfmenu.wave5_agrs_killed = 0;
        level.sfmenu.wave5_claws_killed = 0;
        level.sfmenu.wave5_claws_unlocked = 1;
    }
}

sfshop_get_enemy_spawn_multiplier()
{
    difficulty = getdifficulty();
    if ( difficulty == "easy" )
    {
        return 0.5;
    }
    if ( difficulty == "hard" )
    {
        return 1.5;
    }
    if ( difficulty == "fu" )
    {
        return 2.5;
    }
    return 1.0;
}

sfshop_scale_enemy_spawn_count( base_count )
{
    scaled_count = int( base_count * level.sfmenu.enemy_spawn_multiplier + 0.5 );
    if ( base_count > 0 && scaled_count < 1 )
    {
        scaled_count = 1;
    }
    return scaled_count;
}

sfshop_wave_quota_empty()
{
    return level.sfmenu.wave_soldiers_remaining <= 0 && level.sfmenu.wave_dragonfires_remaining <= 0 && level.sfmenu.wave_agrs_remaining <= 0 && level.sfmenu.wave_claws_remaining <= 0;
}

sfshop_fill_wave_quota()
{
    // Dispatch the difficulty-scaled C.L.A.W. allocation before allowing any
    // other Wave 5 spawn. Once dispatched, randomly interleave soldiers and
    // A.G.R.s. A failed
    // choice is not replaced in the same pass, preventing a ground-spawn burst
    // while a cargo-VTOL slot is temporarily unavailable.
    if ( level.sfmenu.wave_number == 5 )
    {
        if ( level.sfmenu.wave_claws_remaining > 0 )
        {
            return sfshop_spawn_wave_claw();
        }

        if ( level.sfmenu.wave_soldiers_remaining > 0 && level.sfmenu.wave_agrs_remaining > 0 )
        {
            if ( randomint( 2 ) == 0 )
            {
                return sfshop_spawn_wave_infantry();
            }
            return sfshop_spawn_wave_agr();
        }
        if ( level.sfmenu.wave_agrs_remaining > 0 )
        {
            return sfshop_spawn_wave_agr();
        }
        if ( level.sfmenu.wave_soldiers_remaining > 0 )
        {
            return sfshop_spawn_wave_infantry();
        }
        return 0;
    }

    if ( sfshop_spawn_wave_infantry() )
    {
        return 1;
    }
    if ( sfshop_spawn_wave_agr() )
    {
        return 1;
    }
    if ( sfshop_spawn_wave_claw() )
    {
        return 1;
    }
    return 0;
}

sfshop_spawn_wave_infantry()
{
    remaining = level.sfmenu.wave_soldiers_remaining;
    if ( remaining <= 0 )
    {
        return 0;
    }
    if ( getTime() < level.sfmenu.next_enemy_soldier_spawn_time )
    {
        return 0;
    }
    package_name = sfshop_pick_enemy_infantry_package( remaining );
    if ( !isDefined( package_name ) )
    {
        return 0;
    }
    pkg = maps\_so_rts_catalog::package_getpackagebytype( package_name );
    // Ground entry is deliberately limited to one actor per call. The global
    // timestamp keeps every enemy soldier spawn at least two seconds apart.
    expected_units = 1;
    if ( sfshop_spawn_enemy_package( package_name, "GROUND_ENTRY", expected_units, 0, level.sfmenu.wave_number ) )
    {
        level.sfmenu.wave_soldiers_remaining -= expected_units;
        level.sfmenu.next_enemy_soldier_spawn_time = getTime() + level.sfmenu.enemy_soldier_spawn_interval;
        return 1;
    }
    return 0;
}

sfshop_spawn_wave_dragonfire()
{
    remaining = level.sfmenu.wave_dragonfires_remaining;
    if ( remaining < 10 )
    {
        return 0;
    }
    // Keep the stock package at two to avoid its overlapping-unload bug, then
    // expand this one delivered squad to exactly ten Dragonfires in the callback.
    expected_units = 10;
    if ( sfshop_spawn_enemy_package( "quadrotor_pkg", "CARGO_VTOL", expected_units, 10, level.sfmenu.wave_number ) )
    {
        level.sfmenu.wave_dragonfires_remaining -= expected_units;
        return 1;
    }
    return 0;
}

sfshop_spawn_wave_agr()
{
    if ( level.sfmenu.wave_agrs_remaining <= 0 )
    {
        return 0;
    }
    pkg = maps\_so_rts_catalog::package_getpackagebytype( "metalstorm_pkg" );
    if ( !isDefined( pkg ) )
    {
        return 0;
    }
    expected_units = sfshop_enemy_package_size( pkg );
    if ( expected_units > level.sfmenu.wave_agrs_remaining )
    {
        return 0;
    }
    if ( sfshop_spawn_enemy_package( "metalstorm_pkg", "CARGO_VTOL", expected_units, 0, level.sfmenu.wave_number ) )
    {
        level.sfmenu.wave_agrs_remaining -= expected_units;
        return 1;
    }
    return 0;
}

sfshop_spawn_wave_claw()
{
    if ( level.sfmenu.wave_claws_remaining <= 0 )
    {
        return 0;
    }
    pkg = maps\_so_rts_catalog::package_getpackagebytype( "bigdog_pkg" );
    if ( !isDefined( pkg ) )
    {
        return 0;
    }
    expected_units = sfshop_enemy_package_size( pkg );
    if ( expected_units > level.sfmenu.wave_claws_remaining )
    {
        return 0;
    }
    if ( sfshop_spawn_enemy_package( "bigdog_pkg", "CARGO_VTOL", expected_units, 0, level.sfmenu.wave_number ) )
    {
        level.sfmenu.wave_claws_remaining -= expected_units;
        return 1;
    }
    return 0;
}

sfshop_pick_enemy_infantry_package( max_units )
{
    if ( max_units <= 0 )
    {
        return undefined;
    }
    names = [];
    names[ 0 ] = "infantry_enemy_reg_pkg";
    names[ 1 ] = "infantry_enemy_reg2_pkg";
    names[ 2 ] = "infantry_enemy_elite_pkg";
    names[ 3 ] = "infantry_afghan_rpg_pkg";
    names[ 4 ] = "infantry_enemy_ied_pkg";

    start = randomint( names.size );
    i = 0;
    while ( i < names.size )
    {
        name_index = ( start + i ) % names.size;
        pkg = maps\_so_rts_catalog::package_getpackagebytype( names[ name_index ] );
        if ( isDefined( pkg ) && isDefined( pkg.units ) && pkg.units.size > 0 )
        {
            return names[ name_index ];
        }
        i++;
    }
    return undefined;
}

sfshop_wave_intermission( wave, duration, show_white_announcement )
{
    if ( show_white_announcement )
    {
        level.rts.player iprintln( "Wave " + wave + " incoming in " + duration + " seconds!" );
    }
    remaining = duration;
    while ( remaining > 0 )
    {
        sfshop_update_wave_hud( "WAVE " + wave + " STARTS IN " + remaining + " SECONDS" );
        wait 1;
        remaining--;
    }
    if ( show_white_announcement )
    {
        sfshop_announce_wave_start( wave );
    }
    else
    {
        level thread sfshop_play_wave_alarm( wave );
    }
}

sfshop_announce_wave_start( wave )
{
    sfshop_update_wave_hud( "WAVE " + wave + " INCOMING!" );
    level.rts.player iprintlnbold( "Wave " + wave + " incoming!" );
    level thread sfshop_play_wave_alarm( wave );
}

sfshop_play_wave_alarm( wave )
{
    level endon( "rts_terminated" );
    pulses = 1;
    if ( wave == 5 )
    {
        pulses = 3;
    }

    i = 0;
    while ( i < pulses )
    {
        // Use the Drone map's clientside alarm channels. A player playsound call
        // for evt_rts_acoustic_sensor_beep is not audible on this SP map.
        sfshop_set_drone_alarm_channels( 1 );
        wait 0.75;
        sfshop_set_drone_alarm_channels( 0 );
        i++;
        if ( i < pulses )
        {
            wait 0.35;
        }
    }
}

sfshop_set_drone_alarm_channels( enabled )
{
    rpc( "clientscripts/so_rts_mp_drone_amb", "setPOIAlarms", enabled, 1 );
    rpc( "clientscripts/so_rts_mp_drone_amb", "setPOIAlarms", enabled, 2 );
    rpc( "clientscripts/so_rts_mp_drone_amb", "setPOIAlarms", enabled, 3 );
}

sfshop_create_wave_hud()
{
    level.sfmenu.wave_hud = newhudelem();
    level.sfmenu.wave_hud.horzalign = "center";
    level.sfmenu.wave_hud.vertalign = "top";
    level.sfmenu.wave_hud.alignx = "center";
    level.sfmenu.wave_hud.aligny = "top";
    level.sfmenu.wave_hud.x = 0;
    level.sfmenu.wave_hud.y = 28;
    level.sfmenu.wave_hud.fontscale = 1.5;
    level.sfmenu.wave_hud.foreground = 1;
    level.sfmenu.wave_hud.sort = 16;
    level.sfmenu.wave_hud.alpha = 1;
    level.sfmenu.wave_hud.color = ( 1, 0.35, 0.1 );
    level.sfmenu.wave_hud.hidewheninmenu = 1;
}

sfshop_update_wave_hud( text )
{
    if ( isDefined( level.sfmenu.wave_hud ) )
    {
        level.sfmenu.wave_hud settext( text );
    }
}

sfshop_finish_wave_mode()
{
    sfshop_update_wave_hud( "ALL FIVE WAVES CLEARED" );
    level.rts.player iprintlnbold( "All five waves cleared - mission complete!" );
    level.sfmenu.allow_mission_complete = 1;
    level.custom_mission_complete = level.sfmenu.original_mission_complete;
    wait 0.2;
    level thread maps\_so_rts_rules::mission_complete( 1 );
}

sfshop_make_enemy_package_infinite( package_name )
{
    pkg = maps\_so_rts_catalog::package_getpackagebytype( package_name );
    if ( isDefined( pkg ) )
    {
        pkg.qty[ "axis" ] = -1;
        pkg.enforce_deps[ "axis" ] = 0;
        pkg.selectable = 1;
        pkg.max_axis = 64;
    }
}

sfshop_count_active_wave_enemies( wave )
{
    count = 0;
    actors = getaiarray( "axis" );
    i = 0;
    while ( i < actors.size )
    {
        if ( isDefined( actors[ i ] ) && isalive( actors[ i ] ) && actors[ i ] sfshop_entity_belongs_to_wave( wave ) )
        {
            count++;
        }
        i++;
    }

    vehicles = getvehiclearray( "axis" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) && vehicles[ i ] sfshop_entity_belongs_to_wave( wave ) )
        {
            count++;
        }
        i++;
    }
    return count;
}

sfshop_entity_belongs_to_wave( wave )
{
    if ( !isDefined( self.squadid ) || !isDefined( level.rts.squads[ self.squadid ] ) )
    {
        return 0;
    }
    squad = level.rts.squads[ self.squadid ];
    return isDefined( squad.sfshop_enemy_wave ) && isDefined( squad.sfshop_wave_number ) && squad.sfshop_wave_number == wave;
}

sfshop_count_pending_wave_units( wave )
{
    count = 0;
    if ( isDefined( level.rts.transport.helo ) )
    {
        i = 0;
        while ( i < level.rts.transport.helo.size )
        {
            unit = level.rts.transport.helo[ i ];
            if ( sfshop_transport_belongs_to_wave( unit, wave ) )
            {
                count += sfshop_pending_units_for_transport( unit );
            }
            i++;
        }
    }
    if ( isDefined( level.rts.transport.vtol ) )
    {
        i = 0;
        while ( i < level.rts.transport.vtol.size )
        {
            unit = level.rts.transport.vtol[ i ];
            if ( sfshop_transport_belongs_to_wave( unit, wave ) )
            {
                count += sfshop_pending_units_for_transport( unit );
            }
            i++;
        }
    }
    return count;
}

sfshop_transport_belongs_to_wave( unit, wave )
{
    if ( !isDefined( unit ) || !isDefined( unit.squadid ) || !isDefined( level.rts.squads[ unit.squadid ] ) )
    {
        return 0;
    }
    squad = level.rts.squads[ unit.squadid ];
    return isDefined( squad.sfshop_enemy_wave ) && isDefined( squad.sfshop_wave_number ) && squad.sfshop_wave_number == wave;
}

sfshop_pending_units_for_transport( unit )
{
    if ( !isDefined( unit ) || !isDefined( unit.team ) || unit.team != "axis" || ( unit.state != 1 && unit.state != 3 ) || !isDefined( unit.pkg_ref ) )
    {
        return 0;
    }

    pending = sfshop_enemy_package_size( unit.pkg_ref );
    if ( isDefined( unit.squadid ) && isDefined( level.rts.squads[ unit.squadid ] ) && isDefined( level.rts.squads[ unit.squadid ].sfshop_expected_units ) )
    {
        pending = level.rts.squads[ unit.squadid ].sfshop_expected_units;
    }
    if ( isDefined( unit.squadid ) && isDefined( level.rts.squads[ unit.squadid ] ) && isDefined( level.rts.squads[ unit.squadid ].members ) )
    {
        pending -= level.rts.squads[ unit.squadid ].members.size;
    }
    if ( pending < 0 )
    {
        pending = 0;
    }
    return pending;
}

sfshop_count_enemy_type( enemy_type )
{
    count = 0;
    actors = getaiarray( "axis" );
    i = 0;
    while ( i < actors.size )
    {
        if ( isDefined( actors[ i ] ) && isalive( actors[ i ] ) )
        {
            package_name = actors[ i ] sfshop_get_package_name();
            if ( sfshop_package_matches_enemy_type( package_name, enemy_type ) )
            {
                count++;
            }
        }
        i++;
    }

    vehicles = getvehiclearray( "axis" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) )
        {
            package_name = vehicles[ i ] sfshop_get_package_name();
            if ( sfshop_package_matches_enemy_type( package_name, enemy_type ) )
            {
                count++;
            }
        }
        i++;
    }
    count += sfshop_count_pending_enemy_type( enemy_type );
    return count;
}

sfshop_count_pending_enemy_type( enemy_type )
{
    count = 0;
    if ( isDefined( level.rts.transport.helo ) )
    {
        i = 0;
        while ( i < level.rts.transport.helo.size )
        {
            unit = level.rts.transport.helo[ i ];
            if ( isDefined( unit.pkg_ref ) && sfshop_package_matches_enemy_type( unit.pkg_ref.ref, enemy_type ) )
            {
                count += sfshop_pending_units_for_transport( unit );
            }
            i++;
        }
    }
    if ( isDefined( level.rts.transport.vtol ) )
    {
        i = 0;
        while ( i < level.rts.transport.vtol.size )
        {
            unit = level.rts.transport.vtol[ i ];
            if ( isDefined( unit.pkg_ref ) && sfshop_package_matches_enemy_type( unit.pkg_ref.ref, enemy_type ) )
            {
                count += sfshop_pending_units_for_transport( unit );
            }
            i++;
        }
    }
    return count;
}

sfshop_package_matches_enemy_type( package_name, enemy_type )
{
    if ( !isDefined( package_name ) )
    {
        return 0;
    }
    if ( enemy_type == "soldier" )
    {
        return isSubStr( package_name, "infantry_" );
    }
    if ( enemy_type == "dragonfire" )
    {
        return isSubStr( package_name, "quadrotor" );
    }
    if ( enemy_type == "agr" )
    {
        return isSubStr( package_name, "metalstorm" );
    }
    if ( enemy_type == "claw" )
    {
        return isSubStr( package_name, "bigdog" );
    }
    return 0;
}

sfshop_enemy_package_size( pkg )

{
    if ( isDefined( pkg.numunits ) && pkg.numunits > 0 )
    {
        return pkg.numunits;
    }
    if ( isDefined( pkg.units ) && pkg.units.size > 0 )
    {
        return pkg.units.size;
    }
    return 1;
}

sfshop_spawn_enemy_package( package_name, delivery, expected_units, dragonfire_target_size, wave_number )

{
    if ( !isDefined( level.rts.enemy_center ) )
    {
        return 0;
    }

    pkg = maps\_so_rts_catalog::package_getpackagebytype( package_name );
    if ( !isDefined( pkg ) )
    {
        return 0;
    }

    projected_units = expected_units;
    if ( !isDefined( projected_units ) || projected_units <= 0 )
    {
        projected_units = sfshop_enemy_package_size( pkg );
    }
    // Reserve room for the package and its short-lived spawn/unload helpers.
    free_entities = sfshop_refresh_entity_capacity();
    if ( free_entities < level.sfmenu.spawn_pause_threshold + projected_units + 4 )
    {
        return 0;
    }
    if ( delivery == "GROUND_ENTRY" )
    {
        return sfshop_spawn_enemy_ground_package( pkg, projected_units, wave_number );
    }

    if ( sfshop_count_active_deliveries( "axis" ) >= level.sfmenu.max_active_deliveries )
    {
        return 0;
    }

    if ( delivery == "FASTROPE_HELO" )
    {
        transport_type = "helo";
    }
    else
    {
        transport_type = "vtol";
    }

    sfshop_ensure_transport_slots( "axis", transport_type, level.sfmenu.max_active_deliveries );
    if ( !maps\_so_rts_catalog::istransportavailable( "axis", transport_type ) )
    {
        return 0;
    }

    path_start = maps\_so_rts_support::chopper_closest_open_path_start( level.rts.enemy_center.origin, "drop_path_start", "script_unload", "axis", transport_type );
    if ( !isDefined( path_start ) )
    {
        return 0;
    }

    old_delivery = pkg.delivery;
    old_cost = pkg.cost[ "axis" ];
    pkg.delivery = delivery;
    pkg.cost[ "axis" ] = 0;
    pkg.qty[ "axis" ] = -1;
    pkg.enforce_deps[ "axis" ] = 0;
    pkg.selectable = 1;
    pkg.nextavail[ "axis" ] = 0;
    pkg.max_axis = 64;

    squadid = maps\_so_rts_catalog::spawn_package( pkg.ref, "axis", 0, ::sfshop_order_enemy_squad );
    spawn_succeeded = isDefined( squadid ) && squadid != -1 && isDefined( level.rts.squads[ squadid ] );
    if ( spawn_succeeded )
    {
        level.rts.squads[ squadid ].sfshop_managed = 1;
        level.rts.squads[ squadid ].sfshop_enemy_wave = 1;
        level.rts.squads[ squadid ].sfshop_expected_units = projected_units;
        level.rts.squads[ squadid ].sfshop_wave_number = wave_number;
        if ( dragonfire_target_size > 0 )
        {
            level.rts.squads[ squadid ].sfshop_dragonfire_target_size = dragonfire_target_size;
        }
        if ( isSubStr( package_name, "infantry_" ) )
        {
            level.rts.squads[ squadid ].sfshop_prelanding_infantry = 1;
            level thread sfshop_protect_enemy_infantry_delivery( squadid );
        }
    }

    pkg.delivery = old_delivery;
    pkg.cost[ "axis" ] = old_cost;
    pkg.nextavail[ "axis" ] = getTime() + 2000;

    return spawn_succeeded;
}

sfshop_spawn_enemy_ground_package( pkg, projected_units, wave_number )
{
    spawn_locations = getstructarray( "enemy_laststand_spawn_loc", "targetname" );
    if ( !isDefined( spawn_locations ) || spawn_locations.size == 0 )
    {
        return 0;
    }

    // These are the stock Drone mission's edge-entry locations. Prefer the
    // explicitly out-of-bounds entries and keep spawns away from the player.
    outside_locations = [];
    far_locations = [];
    i = 0;
    while ( i < spawn_locations.size )
    {
        location = spawn_locations[ i ];
        far_enough = !isDefined( level.rts.player ) || distancesquared( location.origin, level.rts.player.origin ) > 640000;
        if ( far_enough )
        {
            far_locations[ far_locations.size ] = location;
            if ( isDefined( location.script_noteworthy ) && location.script_noteworthy == "oob_on" )
            {
                outside_locations[ outside_locations.size ] = location;
            }
        }
        i++;
    }

    choices = outside_locations;
    if ( choices.size == 0 )
    {
        choices = far_locations;
    }
    if ( choices.size == 0 )
    {
        choices = spawn_locations;
    }
    // Randomize the entry while refusing to reuse the immediately previous one.
    // Together with the global two-second interval, this spreads soldiers across
    // the map edge instead of repeatedly flooding one outside-map route.
    index = randomint( choices.size );
    if ( choices.size > 1 && index == level.sfmenu.enemy_ground_spawn_index )
    {
        index = ( index + 1 + randomint( choices.size - 1 ) ) % choices.size;
    }
    level.sfmenu.enemy_ground_spawn_index = index;
    spawn_location = choices[ index ];

    pkg.qty[ "axis" ] = -1;
    pkg.enforce_deps[ "axis" ] = 0;
    pkg.selectable = 1;
    pkg.max_axis = 64;
    // Spawn one randomly selected soldier from this package, then immediately
    // restore the shared package array for later shop and wave operations.
    old_units = pkg.units;
    old_numunits = pkg.numunits;
    single_units = [];
    single_units[ 0 ] = old_units[ randomint( old_units.size ) ];
    pkg.units = single_units;
    pkg.numunits = 1;
    squadid = maps\_so_rts_ai::spawn_ai_package_standard( pkg, "axis", undefined, spawn_location.origin );
    pkg.units = old_units;
    pkg.numunits = old_numunits;
    spawn_succeeded = isDefined( squadid ) && squadid != -1 && isDefined( level.rts.squads[ squadid ] );
    if ( !spawn_succeeded )
    {
        return 0;
    }

    squad = level.rts.squads[ squadid ];
    squad.sfshop_managed = 1;
    squad.sfshop_enemy_wave = 1;
    squad.sfshop_expected_units = projected_units;
    squad.sfshop_wave_number = wave_number;
    squad.sfshop_ground_entry = 1;
    if ( isDefined( squad.members ) )
    {
        i = 0;
        while ( i < squad.members.size )
        {
            if ( isDefined( squad.members[ i ] ) )
            {
                // Let the unit walk in from the out-of-bounds entry instead of being
                // deleted by the stock RTS boundary watcher before it reaches combat.
                squad.members[ i ].allow_oob = 1;
                squad.members[ i ].sfshop_managed = 1;
            }
            i++;
        }
    }
    sfshop_order_enemy_squad( squadid );
    return 1;
}

sfshop_order_enemy_squad( squadid )
{
    is_agr_squad = 0;
    if ( isDefined( squadid ) && isDefined( level.rts.squads[ squadid ] ) )
    {
        squad = level.rts.squads[ squadid ];
        is_agr_squad = isDefined( squad.pkg_ref ) && squad.pkg_ref.ref == "metalstorm_pkg";
        squad.sfshop_managed = 1;
        squad.sfshop_enemy_wave = 1;
        is_infantry_delivery = isDefined( squad.sfshop_prelanding_infantry );
        if ( is_infantry_delivery )
        {
            // The stock fast-rope callback fires only after every soldier has
            // unloaded. Keep protection for five more seconds so reward/death
            // tracking has time to initialize before any soldier can be killed.
            squad.sfshop_delivery_complete = 1;
        }
        if ( isDefined( squad.sfshop_dragonfire_target_size ) )
        {
            sfshop_expand_enemy_dragonfire_squad( squadid, squad.sfshop_dragonfire_target_size );
            squad.sfshop_dragonfire_target_size = undefined;
        }
        sfshop_mark_managed_squad_members( squadid );
        sfshop_register_enemy_squad_members( squadid );
        if ( is_infantry_delivery )
        {
            level thread sfshop_release_enemy_infantry_after_delay( squadid );
        }
    }
    maps\_so_rts_enemy::order_new_squad( squadid );
    if ( is_agr_squad && isDefined( squadid ) && isDefined( level.rts.squads[ squadid ] ) && !isDefined( level.rts.squads[ squadid ].sfshop_agr_tracking ) )
    {
        level.rts.squads[ squadid ].sfshop_agr_tracking = 1;
        sfshop_agr_issue_target( squadid );
        level thread sfshop_agr_retarget( squadid );
    }
    else if ( isDefined( squadid ) && isDefined( level.rts.squads[ squadid ] ) && !isDefined( level.rts.squads[ squadid ].sfshop_objective_priority_started ) )
    {
        level.rts.squads[ squadid ].sfshop_objective_priority_started = 1;
        level thread sfshop_enemy_objective_priority_watch( squadid );
    }
}

sfshop_enemy_objective_priority_watch( squadid )
{
    level endon( "rts_terminated" );
    while ( isDefined( level.rts.squads[ squadid ] ) )
    {
        squad = level.rts.squads[ squadid ];
        origin = sfshop_get_live_squad_origin( squadid );
        if ( !isDefined( origin ) )
        {
            return;
        }
        objective = sfshop_find_closest_allied_objective( origin );
        if ( isDefined( objective ) && distancesquared( origin, objective.origin ) > 490000 )
        {
            // Outside 700 units, reaching the objective is the primary order.
            // Normal enemy combat logic remains free to take over once nearby.
            i = 0;
            while ( isDefined( squad.members ) && i < squad.members.size )
            {
                unit = squad.members[ i ];
                if ( isDefined( unit ) && isalive( unit ) )
                {
                    unit.aggressivemode = 1;
                    unit.goalradius = 192;
                    if ( unit isvehicle() )
                    {
                        unit vehclearentitytarget();
                        destination = objective.origin;
                        package_name = unit sfshop_get_package_name();
                        if ( isDefined( package_name ) && isSubStr( package_name, "quadrotor" ) )
                        {
                            destination += ( 0, 0, 72 );
                        }
                        unit setvehgoalpos( destination );
                    }
                    else
                    {
                        unit clearentitytarget();
                        unit setgoalpos( objective.origin );
                    }
                }
                i++;
            }
        }
        wait 2;
    }
}

sfshop_get_live_squad_origin( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || !isDefined( level.rts.squads[ squadid ].members ) )
    {
        return undefined;
    }
    members = level.rts.squads[ squadid ].members;
    i = 0;
    while ( i < members.size )
    {
        if ( isDefined( members[ i ] ) && isalive( members[ i ] ) )
        {
            return members[ i ].origin;
        }
        i++;
    }
    return undefined;
}

sfshop_find_closest_allied_objective( origin )
{
    if ( !isDefined( level.rts.poi ) )
    {
        return undefined;
    }
    closest = undefined;
    closest_distance = 999999999;
    pois = level.rts.poi;
    key = getFirstArrayKey( pois );
    while ( isDefined( key ) )
    {
        poi = pois[ key ];
        valid = isDefined( poi ) && isDefined( poi.entity );
        if ( valid && isDefined( poi.team ) && poi.team != "allies" )
        {
            valid = 0;
        }
        if ( valid && isDefined( poi.ignoreme ) && poi.ignoreme )
        {
            valid = 0;
        }
        if ( valid && isDefined( poi.entity.health ) && poi.entity.health <= 0 )
        {
            valid = 0;
        }
        if ( valid )
        {
            distance_to_objective = distancesquared( origin, poi.entity.origin );
            if ( distance_to_objective < closest_distance )
            {
                closest = poi.entity;
                closest_distance = distance_to_objective;
            }
        }
        key = getNextArrayKey( pois, key );
    }
    return closest;
}

sfshop_register_enemy_squad_members( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || !isDefined( level.rts.squads[ squadid ].members ) )
    {
        return;
    }
    members = level.rts.squads[ squadid ].members;
    i = 0;
    while ( i < members.size )
    {
        if ( isDefined( members[ i ] ) )
        {
            members[ i ] sfshop_register_entity();
        }
        i++;
    }
}

sfshop_protect_enemy_infantry_delivery( squadid )
{
    level endon( "rts_terminated" );

    while ( isDefined( level.rts.squads[ squadid ] ) && !isDefined( level.rts.squads[ squadid ].sfshop_delivery_complete ) )
    {
        squad = level.rts.squads[ squadid ];
        if ( isDefined( squad.members ) )
        {
            i = 0;
            while ( i < squad.members.size )
            {
                if ( isDefined( squad.members[ i ] ) && isalive( squad.members[ i ] ) )
                {
                    squad.members[ i ].sfshop_prelanding_protected = 1;
                    squad.members[ i ].takedamage = 0;
                }
                i++;
            }
        }
        wait 0.05;
    }

    // The unload callback owns the three-second post-landing release.
}

sfshop_release_enemy_infantry_after_delay( squadid )
{
    level endon( "rts_terminated" );
    wait level.sfmenu.enemy_post_land_protection;
    sfshop_release_enemy_infantry_protection( squadid );
}

sfshop_release_enemy_infantry_protection( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || !isDefined( level.rts.squads[ squadid ].members ) )
    {
        return;
    }

    members = level.rts.squads[ squadid ].members;
    i = 0;
    while ( i < members.size )
    {
        if ( isDefined( members[ i ] ) && isDefined( members[ i ].sfshop_prelanding_protected ) )
        {
            members[ i ].sfshop_prelanding_protected = undefined;
            if ( isalive( members[ i ] ) )
            {
                members[ i ].takedamage = 1;
            }
        }
        i++;
    }
}

sfshop_expand_enemy_dragonfire_squad( squadid, target_size )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || target_size <= 0 )
    {
        return;
    }
    pkg = maps\_so_rts_catalog::package_getpackagebytype( "quadrotor_pkg" );
    if ( !isDefined( pkg ) || !isDefined( pkg.units ) || pkg.units.size == 0 )
    {
        return;
    }
    ai_ref = level.rts.ai[ pkg.units[ 0 ] ];
    if ( !isDefined( ai_ref ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    spawn_origin = squad.centerpoint;
    if ( !isDefined( spawn_origin ) && isDefined( squad.members ) && squad.members.size > 0 )
    {
        spawn_origin = squad.members[ 0 ].origin;
    }
    if ( !isDefined( spawn_origin ) )
    {
        spawn_origin = level.rts.enemy_center.origin;
    }

    member_count = 0;
    if ( isDefined( squad.members ) )
    {
        i = 0;
        while ( i < squad.members.size )
        {
            if ( isDefined( squad.members[ i ] ) )
            {
                member_count++;
            }
            i++;
        }
    }

    attempts = 0;
    while ( member_count < target_size && attempts < 16 )
    {
        if ( sfshop_refresh_entity_capacity() < level.sfmenu.spawn_pause_threshold + 4 )
        {
            return;
        }
        offset = sfshop_dragonfire_spawn_offset( attempts );
        quad = maps\_so_rts_support::placevehicle( ai_ref.ref, spawn_origin + offset, "axis" );
        if ( isDefined( quad ) )
        {
            quad.ai_ref = ai_ref;
            quad.sfshop_managed = 1;
            quad maps\_so_rts_squad::addaitosquad( squadid );
            quad maps\_vehicle::defend( spawn_origin );
            quad sfshop_register_entity();
            member_count++;
        }
        attempts++;
    }
}

sfmenu_melee( press_type )
{
    if ( !isDefined( level.sfmenu ) )
    {
        return;
    }

    if ( level.sfmenu.open )
    {
        if ( level.sfmenu.tab != 0 )
        {
            level.sfmenu.tab = 0;
            level.sfmenu.selection = 0;
            sfmenu_draw();
        }
        else
        {
            sfmenu_close( undefined );
        }
        return;
    }

    if ( level.rts.player adsbuttonpressed() )
    {
        sfmenu_open();
        return;
    }

    // Outside the shop, preserve any stock RTS action previously assigned to
    // Melee so this standalone script does not remove mission controls.
    sfmenu_forward_saved_melee( press_type );
}

sfmenu_forward_saved_melee( press_type )
{
    action = undefined;
    if ( press_type == "long" && isDefined( level.sfmenu.saved_melee_long_binding ) )
    {
        action = level.sfmenu.saved_melee_long_binding;
    }
    else if ( press_type == "short" && isDefined( level.sfmenu.saved_melee_binding ) )
    {
        action = level.sfmenu.saved_melee_binding;
    }

    if ( !isDefined( action ) || !isDefined( action.callback ) )
    {
        return;
    }
    if ( isDefined( action.gateflag ) && !common_scripts\utility::flag( action.gateflag ) )
    {
        return;
    }
    [[ action.callback ]]( action.param );
}

sfmenu_open()
{
    if ( level.sfmenu.open )
    {
        return;
    }

    level.sfmenu.open = 1;
    level.sfmenu.saved_bindings = [];

    sfmenu_take_binding( "DPAD_UP" );
    sfmenu_take_binding( "DPAD_DOWN" );
    sfmenu_take_binding( "DPAD_LEFT" );
    sfmenu_take_binding( "DPAD_RIGHT" );
    sfmenu_take_binding( "BUTTON_X" );

    previous_callback = ::sfmenu_previous;
    next_callback = ::sfmenu_next;
    previous_tab_callback = ::sfmenu_previous_tab;
    next_tab_callback = ::sfmenu_next_tab;
    confirm_callback = ::sfmenu_confirm;
    maps\_so_rts_support::registerkeybinding( "DPAD_UP", previous_callback, undefined );
    maps\_so_rts_support::registerkeybinding( "DPAD_DOWN", next_callback, undefined );
    maps\_so_rts_support::registerkeybinding( "DPAD_LEFT", previous_tab_callback, undefined );
    maps\_so_rts_support::registerkeybinding( "DPAD_RIGHT", next_tab_callback, undefined );
    maps\_so_rts_support::registerkeybinding( "BUTTON_X", confirm_callback, undefined );

    sfmenu_draw();
}

sfmenu_take_binding( tag )
{
    if ( isDefined( level.rts.keyactions[ tag ] ) )
    {
        level.sfmenu.saved_bindings[ tag ] = level.rts.keyactions[ tag ];
    }
    else
    {
        level.sfmenu.saved_bindings[ tag ] = undefined;
    }
}

sfmenu_restore_binding( tag )
{
    if ( isDefined( level.sfmenu.saved_bindings[ tag ] ) )
    {
        level.rts.keyactions[ tag ] = level.sfmenu.saved_bindings[ tag ];
    }
    else
    {
        level.rts.keyactions[ tag ] = undefined;
    }
}

sfmenu_close( unused )
{
    if ( !isDefined( level.sfmenu ) || !level.sfmenu.open )
    {
        return;
    }

    level.sfmenu.open = 0;
    sfmenu_restore_binding( "DPAD_UP" );
    sfmenu_restore_binding( "DPAD_DOWN" );
    sfmenu_restore_binding( "DPAD_LEFT" );
    sfmenu_restore_binding( "DPAD_RIGHT" );
    sfmenu_restore_binding( "BUTTON_X" );
    sfmenu_destroy_hud();
}

sfmenu_item_count()
{
    if ( level.sfmenu.tab == 0 )
    {
        return 3;
    }
    return 2;
}

sfmenu_previous( unused )
{
    if ( !level.sfmenu.open )
    {
        return;
    }

    level.sfmenu.selection--;
    if ( level.sfmenu.selection < 0 )
    {
        level.sfmenu.selection = sfmenu_item_count() - 1;
    }
    sfmenu_update_highlight();
}

sfmenu_next( unused )
{
    if ( !level.sfmenu.open )
    {
        return;
    }

    level.sfmenu.selection++;
    if ( level.sfmenu.selection >= sfmenu_item_count() )
    {
        level.sfmenu.selection = 0;
    }
    sfmenu_update_highlight();
}

sfmenu_previous_tab( unused )
{
    if ( !level.sfmenu.open )
    {
        return;
    }
    level.sfmenu.tab--;
    if ( level.sfmenu.tab < 0 )
    {
        level.sfmenu.tab = 1;
    }
    level.sfmenu.selection = 0;
    sfmenu_draw();
}

sfmenu_next_tab( unused )
{
    if ( !level.sfmenu.open )
    {
        return;
    }
    level.sfmenu.tab++;
    if ( level.sfmenu.tab > 1 )
    {
        level.sfmenu.tab = 0;
    }
    level.sfmenu.selection = 0;
    sfmenu_draw();
}

sfmenu_confirm( unused )
{
    if ( !level.sfmenu.open )
    {
        return;
    }

    if ( level.sfmenu.tab == 0 )
    {
        success = sfshop_purchase( level.sfmenu.selection );
    }
    else
    {
        success = sfshop_purchase_scorestreak( level.sfmenu.selection );
    }

    if ( success )
    {
        sfmenu_draw();
    }
}

sfshop_get_price( selection )
{
    switch ( selection )
    {
        case 0:
            return 400;
        case 1:
            return 700;
        case 2:
            return 1500;
    }
    return 0;
}

sfshop_purchase( selection )
{
    price = sfshop_get_price( selection );
    if ( level.sfmenu.points < price )
    {
        level.rts.player iprintlnbold( "Not enough points - need " + price );
        return 0;
    }

    success = 0;
    display_name = "";

    if ( selection == 0 )
    {
        if ( randomint( 2 ) == 0 )
        {
            package_name = "infantry_ally_reg_pkg";
            display_name = "Normal allied infantry";
            fallback_name = "infantry_ally_reg2_pkg";
        }
        else
        {
            package_name = "infantry_ally_reg2_pkg";
            display_name = "Heavy allied infantry";
            fallback_name = "infantry_ally_reg_pkg";
        }

        if ( !isDefined( maps\_so_rts_catalog::package_getpackagebytype( package_name ) ) )
        {
            package_name = fallback_name;
            display_name = "Allied infantry";
        }
        success = sfshop_order_package( package_name, display_name, "FASTROPE_HELO" );
    }
    else if ( selection == 1 )
    {
        display_name = "A.G.R. / A.S.D.";
        success = sfshop_order_package( "metalstorm_pkg", display_name, "CARGO_VTOL" );
    }
    else if ( selection == 2 )
    {
        display_name = "C.L.A.W.";
        success = sfshop_order_package( "bigdog_pkg", display_name, "CARGO_VTOL" );
    }

    if ( !success )
    {
        return 0;
    }

    level.sfmenu.points -= price;
    sfshop_update_points_hud();
    level.rts.player playsound( "evt_command_switch_static_shrt" );
    level.rts.player iprintlnbold( display_name + " purchased for " + price + " - balance " + level.sfmenu.points );
    return 1;
}

sfshop_get_scorestreak_price( selection )
{
    switch ( selection )
    {
        case 0:
            return 2500;
        case 1:
            return 2000;
    }
    return 0;
}

sfshop_scorestreak_owned( selection )
{
    if ( selection == 0 )
    {
        return level.sfmenu.juggernog;
    }
    if ( selection == 1 )
    {
        return level.sfmenu.double_tap;
    }
    return 0;
}

sfshop_purchase_scorestreak( selection )
{
    if ( sfshop_scorestreak_owned( selection ) )
    {
        level.rts.player iprintlnbold( "That allied upgrade is already active" );
        return 0;
    }

    price = sfshop_get_scorestreak_price( selection );
    if ( level.sfmenu.points < price )
    {
        level.rts.player iprintlnbold( "Not enough points - need " + price );
        return 0;
    }

    if ( selection == 0 )
    {
        level.sfmenu.juggernog = 1;
        display_name = "Juggernog";
        sfshop_apply_juggernog_to_all_allies();
    }
    else if ( selection == 1 )
    {
        level.sfmenu.double_tap = 1;
        display_name = "Double Tap";
    }
    else
    {
        return 0;
    }

    level.sfmenu.points -= price;
    sfshop_update_points_hud();
    level.rts.player iprintlnbold( display_name + " activated for all allied units" );
    return 1;
}

sfshop_get_purchase_type( package_name )
{
    if ( package_name == "infantry_ally_reg_pkg" || package_name == "infantry_ally_reg2_pkg" )
    {
        return "infantry";
    }
    if ( package_name == "metalstorm_pkg" )
    {
        return "agr";
    }
    if ( package_name == "bigdog_pkg" )
    {
        return "claw";
    }
    return undefined;
}

sfshop_get_purchase_limit( purchase_type )
{
    if ( purchase_type == "infantry" )
    {
        return 4;
    }
    if ( purchase_type == "agr" )
    {
        return 3;
    }
    if ( purchase_type == "claw" )
    {
        return 2;
    }
    return 0;
}

sfshop_get_active_purchase_count( purchase_type )
{
    if ( purchase_type == "infantry" )
    {
        return level.sfmenu.active_infantry_squads;
    }
    if ( purchase_type == "agr" )
    {
        return level.sfmenu.active_agr;
    }
    if ( purchase_type == "claw" )
    {
        return level.sfmenu.active_claw;
    }
    return 0;
}

sfshop_adjust_active_purchase_count( purchase_type, delta )
{
    if ( purchase_type == "infantry" )
    {
        level.sfmenu.active_infantry_squads += delta;
    }
    else if ( purchase_type == "agr" )
    {
        level.sfmenu.active_agr += delta;
    }
    else if ( purchase_type == "claw" )
    {
        level.sfmenu.active_claw += delta;
    }
    if ( level.sfmenu.active_infantry_squads < 0 )
    {
        level.sfmenu.active_infantry_squads = 0;
    }
    if ( level.sfmenu.active_agr < 0 )
    {
        level.sfmenu.active_agr = 0;
    }
    if ( level.sfmenu.active_claw < 0 )
    {
        level.sfmenu.active_claw = 0;
    }
}

sfshop_order_package( package_name, display_name, forced_delivery )
{
    if ( !sfshop_has_purchase_capacity() )
    {
        level.rts.player iprintlnbold( "Below 200 free entity slots - order cancelled" );
        return 0;
    }

    pkg = maps\_so_rts_catalog::package_getpackagebytype( package_name );
    if ( !isDefined( pkg ) )
    {
        level.rts.player iprintlnbold( display_name + " is unavailable in this mission" );
        return 0;
    }

    purchase_type = sfshop_get_purchase_type( package_name );
    limit = sfshop_get_purchase_limit( purchase_type );
    if ( !isDefined( purchase_type ) || limit == 0 )
    {
        level.rts.player iprintlnbold( display_name + " is not a shop package" );
        return 0;
    }
    if ( sfshop_get_active_purchase_count( purchase_type ) >= limit )
    {
        level.rts.player iprintlnbold( display_name + " limit reached (" + limit + ")" );
        return 0;
    }

    if ( !isDefined( level.rts.allied_center ) )
    {
        level.rts.player iprintlnbold( "Allied reinforcement point is not ready" );
        return 0;
    }

    delivery = pkg.delivery;
    if ( isDefined( forced_delivery ) )
    {
        delivery = forced_delivery;
    }

    if ( delivery == "CARGO_VTOL" || delivery == "FASTROPE_VTOL" )
    {
        sfshop_ensure_transport_slots( "allies", "vtol", level.sfmenu.max_active_deliveries );
        transport_type = "vtol";
    }
    else if ( delivery == "FASTROPE_HELO" )
    {
        sfshop_ensure_transport_slots( "allies", "helo", level.sfmenu.max_active_deliveries );
        transport_type = "helo";
    }
    else
    {
        transport_type = undefined;
    }

    if ( isDefined( transport_type ) )
    {
        if ( sfshop_count_active_deliveries( "allies" ) >= level.sfmenu.max_active_deliveries )
        {
            level.rts.player iprintlnbold( "Five allied deliveries are already active" );
            return 0;
        }
        if ( !maps\_so_rts_catalog::istransportavailable( "allies", transport_type ) )
        {
            level.rts.player iprintlnbold( "Allied transport is busy - try again shortly" );
            return 0;
        }

        path_start = maps\_so_rts_support::chopper_closest_open_path_start( level.rts.allied_center.origin, "drop_path_start", "script_unload", "allies", transport_type );
        if ( !isDefined( path_start ) )
        {
            level.rts.player iprintlnbold( "Allied transport route is busy - try again shortly" );
            return 0;
        }
    }

    old_qty = pkg.qty[ "allies" ];
    old_delivery = pkg.delivery;
    level.sfmenu.purchase_in_progress = 1;
    pkg.qty[ "allies" ] = -1;
    pkg.enforce_deps[ "allies" ] = 0;
    pkg.selectable = 1;
    pkg.nextavail[ "allies" ] = 0;
    pkg.max_friendly = 64;
    pkg.delivery = delivery;

    squadid = maps\_so_rts_catalog::spawn_package( package_name, "allies", 0, ::sfshop_register_purchased_squad );

    pkg.delivery = old_delivery;
    pkg.nextavail[ "allies" ] = 0;
    if ( level.sfmenu.shop_lock_enabled )
    {
        pkg.qty[ "allies" ] = 0;
    }
    else
    {
        pkg.qty[ "allies" ] = old_qty;
    }
    level.sfmenu.purchase_in_progress = 0;

    if ( !isDefined( squadid ) )
    {
        level.rts.player iprintlnbold( display_name + " order failed - no points charged" );
        return 0;
    }

    if ( isDefined( level.rts.squads[ squadid ] ) )
    {
        level.rts.squads[ squadid ].sfshop_managed = 1;
        level.rts.squads[ squadid ].sfshop_purchased = 1;
        level.rts.squads[ squadid ].sfshop_purchase_type = purchase_type;
        level.rts.squads[ squadid ].sfshop_purchase_pending = 1;
    }
    sfshop_adjust_active_purchase_count( purchase_type, 1 );
    level thread sfshop_watch_purchased_squad( squadid, purchase_type );

    return 1;
}

sfshop_register_purchased_squad( squadid )
{
    if ( !isDefined( squadid ) || !isDefined( level.rts.squads[ squadid ] ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    squad.sfshop_managed = 1;
    squad.sfshop_purchased = 1;
    squad.sfshop_purchase_pending = 0;
    sfshop_mark_managed_squad_members( squadid );

    if ( isDefined( squad.pkg_ref ) && squad.pkg_ref.ref == "metalstorm_pkg" && !isDefined( squad.sfshop_agr_tracking ) )
    {
        squad.sfshop_agr_tracking = 1;
        // Purchased A.G.R.s are autonomous assault units. Reissuing this target
        // continuously overrides any player group directive that would hold them
        // beside a selected C.L.A.W.
        sfshop_agr_issue_target( squadid );
        level thread sfshop_agr_retarget( squadid );
    }

}

sfshop_agr_issue_target( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    if ( !isDefined( squad.members ) || squad.members.size == 0 )
    {
        return;
    }
    agr_team = undefined;
    target_origin = undefined;
    i = 0;
    while ( i < squad.members.size )
    {
        agr = squad.members[ i ];
        if ( isDefined( agr ) && isalive( agr ) && isDefined( agr.team ) )
        {
            agr_team = agr.team;
            target_origin = agr.origin;
            break;
        }
        i++;
    }
    if ( !isDefined( agr_team ) || !isDefined( target_origin ) )
    {
        return;
    }
    target = sfshop_find_closest_agr_opponent( agr, agr_team );
    if ( !isDefined( target ) )
    {
        squad.sfshop_agr_target = undefined;
        if ( agr_team == "allies" )
        {
            sfshop_agr_issue_wander( squadid, agr );
        }
        return;
    }
    squad.sfshop_agr_wander_goal = undefined;
    squad.sfshop_agr_next_wander_time = 0;

    if ( !isDefined( squad.sfshop_agr_target ) || squad.sfshop_agr_target != target )
    {
        squad.sfshop_agr_target = target;
        maps\_so_rts_squad::ordersquadattack( squadid, target );
    }
    i = 0;
    while ( i < squad.members.size )
    {
        agr = squad.members[ i ];
        if ( isDefined( agr ) && isalive( agr ) && isDefined( agr.team ) && agr.team == agr_team && isDefined( agr.sfshop_managed ) && agr isvehicle() )
        {
            agr.aggressivemode = 1;
            agr.goalradius = 48;
            agr vehclearentitytarget();
            agr setvehgoalpos( target.origin );
            agr vehsetentitytarget( target );
        }
        i++;
    }
}

sfshop_find_closest_agr_opponent( agr, agr_team )
{
    if ( agr_team == "allies" )
    {
        closest = undefined;
        closest_distance = 999999999;
        actors = getaiarray( "axis" );
        i = 0;
        while ( i < actors.size )
        {
            if ( isDefined( actors[ i ] ) && isalive( actors[ i ] ) && sfshop_agr_can_see_target( agr, actors[ i ] ) )
            {
                distance_to_target = distancesquared( agr.origin, actors[ i ].origin );
                if ( distance_to_target < closest_distance )
                {
                    closest = actors[ i ];
                    closest_distance = distance_to_target;
                }
            }
            i++;
        }
        vehicles = getvehiclearray( "axis" );
        i = 0;
        while ( i < vehicles.size )
        {
            if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) && sfshop_agr_can_see_target( agr, vehicles[ i ] ) )
            {
                distance_to_target = distancesquared( agr.origin, vehicles[ i ].origin );
                if ( distance_to_target < closest_distance )
                {
                    closest = vehicles[ i ];
                    closest_distance = distance_to_target;
                }
            }
            i++;
        }
        return closest;
    }

    origin = agr.origin;
    closest = undefined;
    closest_distance = 999999999;
    actors = getaiarray( "allies" );
    i = 0;
    while ( i < actors.size )
    {
        if ( isDefined( actors[ i ] ) && isalive( actors[ i ] ) )
        {
            distance_to_target = distancesquared( origin, actors[ i ].origin );
            if ( distance_to_target < closest_distance )
            {
                closest = actors[ i ];
                closest_distance = distance_to_target;
            }
        }
        i++;
    }
    vehicles = getvehiclearray( "allies" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) )
        {
            distance_to_target = distancesquared( origin, vehicles[ i ].origin );
            if ( distance_to_target < closest_distance )
            {
                closest = vehicles[ i ];
                closest_distance = distance_to_target;
            }
        }
        i++;
    }
    if ( isDefined( level.rts.player ) && isDefined( level.rts.player.health ) && level.rts.player.health > 0 )
    {
        distance_to_target = distancesquared( origin, level.rts.player.origin );
        if ( distance_to_target < closest_distance )
        {
            closest = level.rts.player;
        }
    }
    return closest;
}

sfshop_agr_can_see_target( agr, target )
{
    if ( !isDefined( agr ) || !isDefined( target ) )
    {
        return 0;
    }
    start = agr.origin + ( 0, 0, 40 );
    end = target.origin + ( 0, 0, 30 );
    return bullettracepassed( start, end, 1, agr, target );
}

sfshop_agr_issue_wander( squadid, lead_agr )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || !isDefined( lead_agr ) )
    {
        return;
    }
    squad = level.rts.squads[ squadid ];
    choose_new_goal = !isDefined( squad.sfshop_agr_wander_goal ) || !isDefined( squad.sfshop_agr_next_wander_time ) || getTime() >= squad.sfshop_agr_next_wander_time;
    if ( !choose_new_goal && distancesquared( lead_agr.origin, squad.sfshop_agr_wander_goal ) < 22500 )
    {
        choose_new_goal = 1;
    }
    if ( choose_new_goal )
    {
        squad.sfshop_agr_wander_goal = sfshop_pick_agr_wander_goal( lead_agr.origin );
        squad.sfshop_agr_next_wander_time = getTime() + randomintrange( 8000, 15001 );
    }
    if ( !isDefined( squad.sfshop_agr_wander_goal ) )
    {
        return;
    }

    i = 0;
    while ( isDefined( squad.members ) && i < squad.members.size )
    {
        agr = squad.members[ i ];
        if ( isDefined( agr ) && isalive( agr ) && isDefined( agr.team ) && agr.team == "allies" && isDefined( agr.sfshop_managed ) && agr isvehicle() )
        {
            agr.aggressivemode = 0;
            agr.goalradius = 128;
            agr vehclearentitytarget();
            agr setvehgoalpos( squad.sfshop_agr_wander_goal );
        }
        i++;
    }
}

sfshop_pick_agr_wander_goal( origin )
{
    points = [];
    if ( isDefined( level.rts.poi ) )
    {
        pois = level.rts.poi;
        key = getFirstArrayKey( pois );
        while ( isDefined( key ) )
        {
            poi = pois[ key ];
            valid = isDefined( poi ) && isDefined( poi.entity );
            if ( valid && isDefined( poi.team ) && poi.team != "allies" )
            {
                valid = 0;
            }
            if ( valid && isDefined( poi.ignoreme ) && poi.ignoreme )
            {
                valid = 0;
            }
            if ( valid && distancesquared( origin, poi.entity.origin ) > 65536 )
            {
                points[ points.size ] = poi.entity.origin;
            }
            key = getNextArrayKey( pois, key );
        }
    }
    if ( points.size > 0 )
    {
        return points[ randomint( points.size ) ];
    }
    return origin + sfshop_soldier_wander_offset( randomint( 8 ) );
}

sfshop_agr_retarget( squadid )
{
    level endon( "rts_terminated" );
    while ( isDefined( level.rts.squads[ squadid ] ) )
    {
        alive = 0;
        squad = level.rts.squads[ squadid ];
        if ( isDefined( squad.members ) )
        {
            i = 0;
            while ( i < squad.members.size )
            {
                if ( isDefined( squad.members[ i ] ) && isalive( squad.members[ i ] ) )
                {
                    alive = 1;
                    break;
                }
                i++;
            }
        }
        if ( !alive )
        {
            return;
        }
        sfshop_agr_issue_target( squadid );
        wait 0.25;
    }
}

sfshop_expire_allied_dragonfire_squad( squadid )
{
    level endon( "rts_terminated" );
    wait level.sfmenu.dragonfire_lifetime;

    if ( !isDefined( level.rts.squads[ squadid ] ) )
    {
        return;
    }
    squad = level.rts.squads[ squadid ];
    if ( !isDefined( squad.sfshop_automatic_dragonfire ) || !isDefined( squad.pkg_ref ) || squad.pkg_ref.ref != "quadrotor_pkg" || !isDefined( squad.members ) )
    {
        return;
    }

    // Work from a local copy because each normal vehicle death callback can
    // remove the dead drone from the live squad array immediately.
    members = squad.members;
    i = 0;
    while ( i < members.size )
    {
        dragonfire = members[ i ];
        if ( isDefined( dragonfire ) && isalive( dragonfire ) && isDefined( dragonfire.team ) && dragonfire.team == "allies" && isDefined( dragonfire.sfshop_managed ) )
        {
            dragonfire kill();
        }
        i++;
    }
}

sfshop_dragonfire_spawn_offset( index )
{
    position = index % 8;
    if ( position == 0 )
    {
        return ( 96, 0, 64 );
    }
    if ( position == 1 )
    {
        return ( -96, 0, 64 );
    }
    if ( position == 2 )
    {
        return ( 0, 96, 72 );
    }
    if ( position == 3 )
    {
        return ( 0, -96, 72 );
    }
    if ( position == 4 )
    {
        return ( 68, 68, 88 );
    }
    if ( position == 5 )
    {
        return ( -68, 68, 88 );
    }
    if ( position == 6 )
    {
        return ( 68, -68, 96 );
    }
    return ( -68, -68, 96 );
}

sfshop_mark_managed_squad_members( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) || !isDefined( level.rts.squads[ squadid ].members ) )
    {
        return;
    }

    members = level.rts.squads[ squadid ].members;
    i = 0;
    while ( i < members.size )
    {
        if ( isDefined( members[ i ] ) )
        {
            members[ i ].sfshop_managed = 1;
            if ( !isDefined( members[ i ].sfshop_cleanup_started ) )
            {
                members[ i ].sfshop_cleanup_started = 1;
                members[ i ] thread sfshop_cleanup_managed_entity();
            }
        }
        i++;
    }
}

sfshop_watch_purchased_squad( squadid, purchase_type )
{
    level endon( "rts_terminated" );
    delivered = 0;

    while ( isDefined( level.rts.squads[ squadid ] ) )
    {
        squad = level.rts.squads[ squadid ];
        live_members = 0;
        if ( isDefined( squad.members ) )
        {
            i = 0;
            while ( i < squad.members.size )
            {
                if ( isDefined( squad.members[ i ] ) && isalive( squad.members[ i ] ) )
                {
                    live_members++;
                }
                i++;
            }
        }

        if ( live_members > 0 )
        {
            delivered = 1;
        }

        if ( delivered && live_members == 0 )
        {
            break;
        }
        if ( !delivered && !sfshop_squad_in_active_transport( squadid ) )
        {
            // A delivery that never unloaded should not consume a purchase slot.
            break;
        }
        wait 0.5;
    }

    sfshop_adjust_active_purchase_count( purchase_type, -1 );
    if ( isDefined( level.rts.squads[ squadid ] ) )
    {
        level.rts.squads[ squadid ].sfshop_purchased = undefined;
        level.rts.squads[ squadid ].sfshop_purchase_pending = undefined;
    }
}

sfshop_squad_in_active_transport( squadid )
{
    if ( isDefined( level.rts.transport.helo ) )
    {
        i = 0;
        while ( i < level.rts.transport.helo.size )
        {
            unit = level.rts.transport.helo[ i ];
            if ( isDefined( unit.squadid ) && unit.squadid == squadid && ( unit.state == 1 || unit.state == 3 ) )
            {
                return 1;
            }
            i++;
        }
    }
    if ( isDefined( level.rts.transport.vtol ) )
    {
        i = 0;
        while ( i < level.rts.transport.vtol.size )
        {
            unit = level.rts.transport.vtol[ i ];
            if ( isDefined( unit.squadid ) && unit.squadid == squadid && ( unit.state == 1 || unit.state == 3 ) )
            {
                return 1;
            }
            i++;
        }
    }
    return 0;
}

sfshop_count_active_deliveries( team )
{
    count = 0;
    if ( isDefined( level.rts.transport.helo ) )
    {
        i = 0;
        while ( i < level.rts.transport.helo.size )
        {
            unit = level.rts.transport.helo[ i ];
            if ( isDefined( unit.team ) && unit.team == team && ( unit.state == 1 || unit.state == 3 ) )
            {
                count++;
            }
            i++;
        }
    }
    if ( isDefined( level.rts.transport.vtol ) )
    {
        i = 0;
        while ( i < level.rts.transport.vtol.size )
        {
            unit = level.rts.transport.vtol[ i ];
            if ( isDefined( unit.team ) && unit.team == team && ( unit.state == 1 || unit.state == 3 ) )
            {
                count++;
            }
            i++;
        }
    }
    return count;
}

sfshop_dragonfire_issue_target( squadid )
{
    if ( !isDefined( level.rts.squads[ squadid ] ) )
    {
        return;
    }

    squad = level.rts.squads[ squadid ];
    if ( !isDefined( squad.members ) || squad.members.size == 0 )
    {
        return;
    }

    target_origin = squad.centerpoint;
    if ( !isDefined( target_origin ) )
    {
        target_origin = squad.members[ 0 ].origin;
    }
    target = sfshop_find_closest_enemy( target_origin );
    if ( !isDefined( target ) )
    {
        squad.sfshop_dragonfire_target = undefined;
        return;
    }

    if ( !isDefined( squad.sfshop_dragonfire_target ) || squad.sfshop_dragonfire_target != target )
    {
        squad.sfshop_dragonfire_target = target;
        // Let the stock squad command select navigable vehicle nodes. The old
        // direct setvehgoalpos loop repeatedly drew a straight line through walls.
        maps\_so_rts_squad::ordersquadattack( squadid, target );
    }
}

sfshop_dragonfire_retarget( squadid )
{
    level endon( "rts_terminated" );
    while ( isDefined( level.rts.squads[ squadid ] ) )
    {
        alive = 0;
        squad = level.rts.squads[ squadid ];
        if ( isDefined( squad.members ) )
        {
            i = 0;
            while ( i < squad.members.size )
            {
                if ( isDefined( squad.members[ i ] ) && isalive( squad.members[ i ] ) )
                {
                    alive = 1;
                    break;
                }
                i++;
            }
        }
        if ( !alive )
        {
            return;
        }
        sfshop_dragonfire_issue_target( squadid );
        wait 0.25;
    }
}

sfshop_find_closest_enemy( origin )
{
    closest = undefined;
    closest_distance = 999999999;
    actors = getaiarray( "axis" );
    i = 0;
    while ( i < actors.size )
    {
        if ( isDefined( actors[ i ] ) && isalive( actors[ i ] ) )
        {
            distance_to_target = distancesquared( origin, actors[ i ].origin );
            if ( distance_to_target < closest_distance )
            {
                closest = actors[ i ];
                closest_distance = distance_to_target;
            }
        }
        i++;
    }
    vehicles = getvehiclearray( "axis" );
    i = 0;
    while ( i < vehicles.size )
    {
        if ( isDefined( vehicles[ i ] ) && isalive( vehicles[ i ] ) )
        {
            distance_to_target = distancesquared( origin, vehicles[ i ].origin );
            if ( distance_to_target < closest_distance )
            {
                closest = vehicles[ i ];
                closest_distance = distance_to_target;
            }
        }
        i++;
    }
    return closest;
}

sfshop_ensure_transport_slots( team, type, desired_count )
{
    count = 0;
    if ( type == "helo" )
    {
        transports = level.rts.transport.helo;
    }
    else
    {
        transports = level.rts.transport.vtol;
    }

    i = 0;
    while ( i < transports.size )
    {
        if ( transports[ i ].team == team )
        {
            count++;
        }
        i++;
    }

    while ( count < desired_count )
    {
        unit = spawnstruct();
        unit.state = 0;
        unit.type = type;
        unit.team = team;

        if ( type == "helo" )
        {
            index = level.rts.transport.helo.size;
            unit.num = index;
            level.rts.transport.helo[ index ] = unit;
        }
        else
        {
            index = level.rts.transport.vtol.size;
            unit.num = index;
            level.rts.transport.vtol[ index ] = unit;
        }

        level thread maps\_so_rts_catalog::transportthink( unit );
        count++;
    }
}

sfmenu_draw()
{
    sfmenu_destroy_hud();

    level.sfmenu.background = newhudelem();
    level.sfmenu.background.horzalign = "center";
    level.sfmenu.background.vertalign = "middle";
    level.sfmenu.background.alignx = "center";
    level.sfmenu.background.aligny = "middle";
    level.sfmenu.background.x = 0;
    level.sfmenu.background.y = -5;
    level.sfmenu.background.alpha = 0.78;
    level.sfmenu.background.color = ( 0, 0, 0 );
    level.sfmenu.background.sort = 18;
    level.sfmenu.background.hidewheninmenu = 1;
    level.sfmenu.background setshader( "white", 520, 350 );
    level.sfmenu.hud[ level.sfmenu.hud.size ] = level.sfmenu.background;

    level.sfmenu.hud[ level.sfmenu.hud.size ] = sfmenu_make_text( -158, "STRIKE FORCE SHOP", 1.85, ( 1, 0.55, 0.1 ) );
    if ( level.sfmenu.tab == 0 )
    {
        level.sfmenu.hud[ level.sfmenu.hud.size ] = sfmenu_make_text( -141, "[ TROOPS ]     SCORESTREAKS", 1.05, ( 1, 0.75, 0.25 ) );
    }
    else
    {
        level.sfmenu.hud[ level.sfmenu.hud.size ] = sfmenu_make_text( -141, "TROOPS     [ SCORESTREAKS ]", 1.05, ( 1, 0.75, 0.25 ) );
    }
    level.sfmenu.balance = sfmenu_make_text( -128, "AVAILABLE POINTS: " + level.sfmenu.points, 1.35, ( 1, 0.8, 0.2 ) );
    level.sfmenu.hud[ level.sfmenu.hud.size ] = level.sfmenu.balance;
    if ( level.sfmenu.tab == 0 )
    {
        level.sfmenu.items[ 0 ] = sfmenu_make_text( -67, "RANDOM NORMAL / HEAVY TROOPS  -  400 (4 SQUADS)", 1.2, ( 0.7, 0.7, 0.7 ) );
        level.sfmenu.items[ 1 ] = sfmenu_make_text( -22, "A.G.R. / A.S.D.  -  700 (3 MAX)", 1.2, ( 0.7, 0.7, 0.7 ) );
        level.sfmenu.items[ 2 ] = sfmenu_make_text( 23, "C.L.A.W.  -  1500 (2 MAX)", 1.2, ( 0.7, 0.7, 0.7 ) );
    }
    else
    {
        juggernog_status = "";
        double_tap_status = "";
        if ( level.sfmenu.juggernog )
        {
            juggernog_status = "  [ACTIVE]";
        }
        if ( level.sfmenu.double_tap )
        {
            double_tap_status = "  [ACTIVE]";
        }
        level.sfmenu.items[ 0 ] = sfmenu_make_text( -67, "JUGGERNOG: ALL ALLIES +2.5x HEALTH  -  2500" + juggernog_status, 1.15, ( 0.7, 0.7, 0.7 ) );
        level.sfmenu.items[ 1 ] = sfmenu_make_text( 3, "DOUBLE TAP: ALLIED DAMAGE x2  -  2000" + double_tap_status, 1.15, ( 0.7, 0.7, 0.7 ) );
    }

    i = 0;
    while ( i < level.sfmenu.items.size )
    {
        level.sfmenu.hud[ level.sfmenu.hud.size ] = level.sfmenu.items[ i ];
        i++;
    }

    level.sfmenu.hud[ level.sfmenu.hud.size ] = sfmenu_make_text( 132, "LEFT/RIGHT: TAB    UP/DOWN: SELECT    USE: BUY", 1.1, ( 0.8, 0.8, 0.8 ) );
    level.sfmenu.hud[ level.sfmenu.hud.size ] = sfmenu_make_text( 156, "MELEE: BACK / EXIT", 1.05, ( 0.55, 0.55, 0.55 ) );
    sfmenu_update_highlight();
}

sfmenu_make_text( y, text, scale, color )
{
    elem = newhudelem();
    elem.horzalign = "center";
    elem.vertalign = "middle";
    elem.alignx = "center";
    elem.aligny = "middle";
    elem.x = 0;
    elem.y = y;
    elem.fontscale = scale;
    elem.foreground = 1;
    elem.sort = 20;
    elem.alpha = 1;
    elem.color = color;
    elem.hidewheninmenu = 1;
    elem settext( text );
    return elem;
}

sfmenu_update_highlight()
{
    i = 0;
    while ( i < level.sfmenu.items.size )
    {
        level.sfmenu.items[ i ].color = ( 0.7, 0.7, 0.7 );
        i++;
    }
    level.sfmenu.items[ level.sfmenu.selection ].color = ( 1, 0.55, 0.1 );
}

sfmenu_destroy_hud()
{
    if ( !isDefined( level.sfmenu.hud ) )
    {
        level.sfmenu.hud = [];
        level.sfmenu.items = [];
        level.sfmenu.balance = undefined;
        return;
    }

    i = 0;
    while ( i < level.sfmenu.hud.size )
    {
        if ( isDefined( level.sfmenu.hud[ i ] ) )
        {
            level.sfmenu.hud[ i ] destroy();
        }
        i++;
    }

    level.sfmenu.hud = [];
    level.sfmenu.items = [];
    level.sfmenu.balance = undefined;
}
