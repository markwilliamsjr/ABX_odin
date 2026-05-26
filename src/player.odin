package main

import sdl "vendor:sdl2"

// ---- Types ----
Player :: struct {
	x, y, speed:                                                  f32,
	width, height, hb_offset_x, hb_offset_y, hb_width, hb_height: int,
	active:                                                       bool,
	current_ammo:                                                 WeaponType,
}

WeaponType :: enum {
	Neutral,
	// PCN,
	// PMX,
}

WeaponDefinition :: struct {
	weapon_type:                                                         WeaponType,
	bullet_texture_path:                                                 string,
	ship_texture_path:                                                   string,
	damage_effective, damage_neutral, damage_ineffective, width, height: int,
	speed:                                                               f32,
}

Bullet :: struct {
	x, y, speed:   f32,
	width, height: int,
	active:        bool,
	weapon_type:   WeaponType,
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

bullet_init :: proc(player: ^Player) -> Bullet {
	def := get_weapon_def(player.current_ammo)
	b := Bullet {
		width       = def.width,
		height      = def.height,
		speed       = def.speed,
		active      = true,
		weapon_type = player.current_ammo,
	}
	b.x = player.x + (f32(player.width) / 2.0) - (f32(b.width) / 2.0)
	b.y = player.y
	return b
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

bullet_update :: proc(b: ^Bullet, delta_time: f32) {
	b.y -= b.speed * delta_time
	if (b.y + f32(b.height) < 0) {
		b.active = false
	}
}

// ---- Helpers ----

get_weapon_def :: proc(weapon_type: WeaponType) -> ^WeaponDefinition {
	return &WEAPON_DEFS[weapon_type]
}

