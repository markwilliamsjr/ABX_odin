package main

import sdl "vendor:sdl2"

// ---- Types ----
Player :: struct {
	x, y, speed:                                                  f32,
	width, height, hb_offset_x, hb_offset_y, hb_width, hb_height: int,
	active:                                                       bool,
	current_ammo:                                                 WeaponType,
	was_firing:                                                   bool,
}

WeaponType :: enum {
	Neutral,
	PCN,
	PMX,
}

WeaponDefinition :: struct {
	weapon_type:                                                         WeaponType,
	bullet_texture_path:                                                 string,
	ship_texture_path:                                                   string,
	damage_effective, damage_neutral, damage_ineffective, width, height: int,
	speed:                                                               f32,
}

Bullets :: struct {
	x, y, speed:   [MAX_BULLETS]f32,
	weapon_type:   [MAX_BULLETS]WeaponType,
	width, height: [MAX_BULLETS]int,
	count:         int,
}

// ---- Definitions / Tables ----

WEAPON_DEFS := [WeaponType]WeaponDefinition {
	.Neutral = {
		weapon_type = .Neutral,
		bullet_texture_path = "assets/weapons/base_shot.png",
		ship_texture_path = "assets/ships/ship_neutral.png",
		damage_effective = 3,
		damage_neutral = 3,
		damage_ineffective = 3,
		width = 8,
		height = 23,
		speed = 300.0,
	},
	.PCN = {
		weapon_type = .PCN,
		bullet_texture_path = "assets/weapons/pcn_shot.png",
		ship_texture_path = "assets/ships/ship_pcn.png",
		damage_effective = 6,
		damage_neutral = 3,
		damage_ineffective = 2,
		width = 8,
		height = 8,
		speed = 300.0,
	},
	.PMX = {
		weapon_type = .PMX,
		bullet_texture_path = "assets/weapons/pmx_shot.png",
		ship_texture_path = "assets/ships/ship_pmx.png",
		damage_effective = 6,
		damage_neutral = 3,
		damage_ineffective = 2,
		width = 8,
		height = 8,
		speed = 300.0,
	},
}

// ---- Init ----

player_init :: proc(screen_width: int, screen_height: int) -> Player {
	p := Player {
		width        = 64,
		height       = 128,
		hb_width     = 22,
		hb_height    = 65,
		speed        = 300,
		active       = true,
		current_ammo = .Neutral,
	}
	p.x = (f32(screen_width) / 2) - (f32(p.width) / 2)
	p.y = f32(screen_height - p.height - 20)
	p.hb_offset_x = (p.width - p.hb_width) / 2
	p.hb_offset_y = (p.height - p.hb_height) / 2 + 10

	return p
}

bullet_init :: proc(bullet: ^Bullets, player: ^Player) {
	if bullet.count == MAX_BULLETS {
		return
	}
	wep_def := get_weapon_def(player.current_ammo)

	bullet.x[bullet.count] = player.x + (f32(player.width) / 2) - (f32(wep_def.width) / 2)
	bullet.y[bullet.count] = player.y
	bullet.speed[bullet.count] = wep_def.speed
	bullet.weapon_type[bullet.count] = player.current_ammo
	bullet.width[bullet.count] = wep_def.width
	bullet.height[bullet.count] = wep_def.height
	bullet.count += 1
}
// ---- Update ----

player_update :: proc(p: ^Player, keystate: [^]u8, delta_time: f32) {
	if keystate[sdl.SCANCODE_LEFT] != 0 || keystate[sdl.SCANCODE_A] != 0 {
		p.x -= p.speed * delta_time
	}
	if keystate[sdl.SCANCODE_RIGHT] != 0 || keystate[sdl.SCANCODE_D] != 0 {
		p.x += p.speed * delta_time
	}
	if (p.x < 0) {
		p.x = 0
	}
	if (p.x + f32(p.width) > SCREEN_WIDTH) {
		p.x = f32(SCREEN_WIDTH) - f32(p.width)
	}
}

bullet_update :: proc(bullets: ^Bullets, delta_time: f32) {
	for i := bullets.count - 1; i >= 0; i -= 1 {
		wep_def := get_weapon_def(bullets.weapon_type[i])
		bullets.y[i] -= bullets.speed[i] * delta_time
		if bullets.y[i] + f32(wep_def.height) <= 0 {
			bullet_remove(bullets, i)
		}
	}
}
// ---- Helpers ----

get_weapon_def :: proc(weapon_type: WeaponType) -> ^WeaponDefinition {
	return &WEAPON_DEFS[weapon_type]
}

bullet_remove :: proc(bullet: ^Bullets, index: int) {
	last := bullet.count - 1
	bullet.x[index] = bullet.x[last]
	bullet.y[index] = bullet.y[last]
	bullet.width[index] = bullet.width[last]
	bullet.height[index] = bullet.height[last]
	bullet.speed[index] = bullet.speed[last]
	bullet.weapon_type[index] = bullet.weapon_type[last]
	bullet.count -= 1
}

player_fire_bullet :: proc(player: ^Player, bullet: ^Bullets, keystate: [^]u8) {
	if keystate[sdl.SCANCODE_SPACE] != 0 && !player.was_firing {
		player.was_firing = true
		bullet_init(bullet, player)
	}
	if keystate[sdl.SCANCODE_SPACE] == 0 {
		player.was_firing = false
	}
}
