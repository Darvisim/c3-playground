module main;

import std, raylib6;

const RLColor[5] ROW_COLORS = { rl::RED, rl::ORANGE, rl::YELLOW, rl::GREEN, rl::SKYBLUE };

enum State : int { READY, PLAYING, PAUSED, GAMEOVER, VICTORY }

struct Particle
{
	bool active;
	Vec2 pos;
	Vec2 vel;
	float life;
	float max_life;
	RLColor color;
}

struct Brick
{
	bool active;
	Rect bounds;
	RLColor color;
	int points;
}

struct GameState
{
	State state;
	Vec2 pad_pos;
	Vec2 ball_pos;
	Vec2 ball_vel;
	float ball_radius;
	bool launched;

	Brick[12][5] bricks;
	Particle[128] particles;

	int score;
	int lives;
	int combo;
	int active_bricks;
	float shake;
}

GameState g;
RLSound snd_bounce;
RLSound snd_brick;
RLSound snd_lose;
RLSound snd_win;

fn RLSound make_sound(float f1, float f2, float dur, float amp = 0.25f) => @pool()
{
	sz len = (sz)(dur * 44100.0f);
	float[] pcm = mem::temp_array(float, len);

	float phase = 0.0f;
	for (sz i = 0; i < len; i++)
	{
		float t = (float)i / (float)len;
		phase += (f1 + (f2 - f1) * t) * 6.283185f / 44100.0f;
		pcm[i] = math::sin(phase) * (1.0f - t) * amp;
	}
	return rl::load_sound_from_wave({ .frameCount = (uint)len, .sample_rate = 44100, .sample_size = 32, .channels = 1, .data = pcm.ptr });
}

fn void GameState.spawn_particles(&self, Vec2 pos, RLColor col, int count, float spd_mult = 1.0f)
{
	for (int i = 0; i < count; i++)
	{
		foreach (&p : self.particles)
		{
			if (!p.active)
			{
				float a = (float)rnd() * 6.283185f;
				float spd = (50.0f + (float)rnd() * 180.0f) * spd_mult;
				*p = { .active = true, .pos = pos, .vel = { math::cos(a) * spd, math::sin(a) * spd }, .life = 0.3f + (float)rnd() * 0.3f, .max_life = 0.6f, .color = col };
				break;
			}
		}
	}
}

fn void GameState.reset_ball(&self)
{
	self.pad_pos     = { 400.0f, 414.0f };
	self.ball_pos    = { 400.0f, 398.0f };
	self.ball_vel    = { 0.0f, 0.0f };
	self.ball_radius = 6.5f;
	self.launched    = false;
}

fn void GameState.init(&self)
{
	self.state = READY;
	self.lives = 3;
	self.score = 0;
	self.combo = 0;
	self.shake = 0.0f;
	self.active_bricks = 60;
	self.reset_ball();

	foreach (&p : self.particles) p.active = false;

	for (int r = 0; r < 5; r++)
	{
		for (int c = 0; c < 12; c++)
		{
			self.bricks[r][c] = {
				.active = true,
				.bounds = { 18.0f + (float)c * 64.0f, 54.0f + (float)r * 24.0f, 58.0f, 18.0f },
				.color  = ROW_COLORS[r],
				.points = (5 - r) * 15
			};
		}
	}
}

fn void GameState.update(&self, float dt)
{
	if (self.shake > 0.0f) self.shake = math::max(0.0f, self.shake - dt * 8.0f);

	foreach (&p : self.particles)
	{
		if (!p.active) continue;
		p.pos += p.vel * dt;
		p.life -= dt;
		if (p.life <= 0.0f) p.active = false;
	}

	if (rl::is_key_pressed(P) && (self.state == PLAYING || self.state == PAUSED))
	{
		self.state = (self.state == PAUSED) ? PLAYING : PAUSED;
	}
	if (self.state == PAUSED) return;

	if (self.state == GAMEOVER || self.state == VICTORY)
	{
		if (rl::is_key_pressed(ENTER) || rl::is_key_pressed(SPACE) || rl::is_mouse_button_pressed(LEFT)) self.init();
		return;
	}

	// Paddle Controls
	Vec2 md = rl::get_mouse_delta();
	if (math::abs(md.x) > 0.5f || rl::is_mouse_button_down(LEFT))
	{
		self.pad_pos.x = rl::get_mouse_position().x;
	}
	else
	{
		if (rl::is_key_down(A) || rl::is_key_down(LEFT))  self.pad_pos.x -= 550.0f * dt;
		if (rl::is_key_down(D) || rl::is_key_down(RIGHT)) self.pad_pos.x += 550.0f * dt;
	}
	self.pad_pos.x = math::clamp(self.pad_pos.x, 57.0f, 743.0f);

	// Ball Launching
	if (!self.launched)
	{
		self.ball_pos = { self.pad_pos.x, self.pad_pos.y - 16.0f };
		if (rl::is_key_pressed(SPACE) || rl::is_key_pressed(UP) || rl::is_key_pressed(W) || rl::is_mouse_button_pressed(LEFT))
		{
			float a = -1.570796f + ((float)rnd() - 0.5f) * 0.5f;
			self.ball_vel = { math::cos(a) * 380.0f, math::sin(a) * 380.0f };
			self.launched = true;
			self.state = PLAYING;
			rl::play_sound(snd_bounce);
		}
		return;
	}

	self.ball_pos += self.ball_vel * dt;
	if (rnd() < 0.4) self.spawn_particles(self.ball_pos, rl::GOLD, 1, 0.2f);

	// Wall Collisions
	if (self.ball_pos.x - self.ball_radius <= 10.0f)     { self.ball_pos.x = 10.0f + self.ball_radius;  self.ball_vel.x = math::abs(self.ball_vel.x);  rl::play_sound(snd_bounce); }
	if (self.ball_pos.x + self.ball_radius >= 790.0f)    { self.ball_pos.x = 790.0f - self.ball_radius; self.ball_vel.x = -math::abs(self.ball_vel.x); rl::play_sound(snd_bounce); }
	if (self.ball_pos.y - self.ball_radius <= 10.0f)     { self.ball_pos.y = 10.0f + self.ball_radius;  self.ball_vel.y = math::abs(self.ball_vel.y);  rl::play_sound(snd_bounce); }
	else if (self.ball_pos.y - self.ball_radius > 450.0f)
	{
		self.lives--;
		self.combo = 0;
		self.shake = 6.0f;
		self.spawn_particles(self.ball_pos, rl::RED, 24, 1.4f);
		rl::play_sound(snd_lose);

		if (self.lives <= 0)
		{
			self.state = GAMEOVER;
		}
		else
		{
			self.reset_ball();
			self.state = READY;
		}
		return;
	}

	// Paddle Collision
	Rect pad_rec = { self.pad_pos.x - 47.0f, self.pad_pos.y - 7.0f, 94.0f, 14.0f };
	if (rl::check_collision_circle_rec(self.ball_pos, self.ball_radius, pad_rec) && self.ball_vel.y > 0.0f)
	{
		float offset = (self.ball_pos.x - self.pad_pos.x) / 47.0f;
		float angle = -1.570796f + math::clamp(offset, -0.85f, 0.85f) * 1.1f;
		float speed = math::min(self.ball_vel.length() * 1.015f, 580.0f);

		self.ball_vel = { math::cos(angle) * speed, math::sin(angle) * speed };
		self.ball_pos.y = pad_rec.y - self.ball_radius;
		self.combo = 0;
		self.spawn_particles(self.ball_pos, rl::SKYBLUE, 8, 0.6f);
		rl::play_sound(snd_bounce);
	}

	// Brick Collisions
	for (int r = 0; r < 5; r++)
	{
		for (int c = 0; c < 12; c++)
		{
			Brick* b = &self.bricks[r][c];
			if (!b.active) continue;

			if (rl::check_collision_circle_rec(self.ball_pos, self.ball_radius, b.bounds))
			{
				b.active = false;
				self.active_bricks--;
				self.combo++;
				self.score += b.points * self.combo;
				self.shake = math::min(self.shake + 1.2f, 4.0f);
				self.spawn_particles({ b.bounds.x + 29.0f, b.bounds.y + 9.0f }, b.color, 16, 1.2f);
				rl::play_sound(snd_brick);

				float nx = math::clamp(self.ball_pos.x, b.bounds.x, b.bounds.x + b.bounds.width);
				float ny = math::clamp(self.ball_pos.y, b.bounds.y, b.bounds.y + b.bounds.height);
				if (math::abs(self.ball_pos.x - nx) > math::abs(self.ball_pos.y - ny))
				{
					self.ball_vel.x *= -1.0f;
				}
				else
				{
					self.ball_vel.y *= -1.0f;
				}

				if (self.active_bricks <= 0) { self.state = VICTORY; rl::play_sound(snd_win); }
				return;
			}
		}
	}
}

fn void draw_centered(ZString text, int y, int size, RLColor col)
{
	rl::draw_text(text, 400 - rl::measure_text(text, size) / 2, y, size, col);
}

fn void GameState.draw(&self)
{
	Vec2 s = self.shake > 0.05f ? (Vec2){ ((float)rnd() - 0.5f) * self.shake * 2.0f, ((float)rnd() - 0.5f) * self.shake * 2.0f } : { 0.0f, 0.0f };

	// Grid & Arena
	for (int x = 10; x < 800; x += 40) rl::draw_line_v({ (float)x + s.x, s.y }, { (float)x + s.x, 450.0f + s.y }, (RLColor){ 22, 30, 48, 255 });
	for (int y = 10; y < 450; y += 40) rl::draw_line_v({ s.x, (float)y + s.y }, { 800.0f + s.x, (float)y + s.y }, (RLColor){ 22, 30, 48, 255 });
	rl::draw_rectangle_lines_ex({ 10.0f + s.x, 10.0f + s.y, 780.0f, 430.0f }, 2.0f, (RLColor){ 30, 41, 59, 255 });

	// Particles
	foreach (p : self.particles)
	{
		if (!p.active) continue;
		RLColor c = p.color;
		c.a = (char)((p.life / p.max_life) * 255.0f);
		rl::draw_circle_v(p.pos + s, 2.5f, c);
	}

	// Bricks
	for (int r = 0; r < 5; r++)
	{
		for (int c = 0; c < 12; c++)
		{
			Brick b = self.bricks[r][c];
			if (!b.active) continue;
			Rect rec = { b.bounds.x + s.x, b.bounds.y + s.y, b.bounds.width, b.bounds.height };
			rl::draw_rectangle_rounded(rec, 0.35f, 4, b.color);
			rl::draw_rectangle_rounded_lines_ex(rec, 0.35f, 4, 1.0f, (RLColor){ 255, 255, 255, 80 });
		}
	}

	// Paddle & Ball
	Rect pad = { self.pad_pos.x - 47.0f + s.x, self.pad_pos.y - 7.0f + s.y, 94.0f, 14.0f };
	rl::draw_rectangle_rounded(pad, 0.5f, 6, rl::SKYBLUE);
	rl::draw_rectangle_rounded_lines_ex(pad, 0.5f, 6, 1.5f, rl::WHITE);

	rl::draw_circle_v(self.ball_pos + s, self.ball_radius + 2.0f, (RLColor){ 250, 204, 21, 200 });
	rl::draw_circle_v(self.ball_pos + s, self.ball_radius, rl::WHITE);

	// HUD
	rl::draw_text(rl::text_format("SCORE: %05d", self.score), 24, 20, 20, (RLColor){ 248, 250, 252, 255 });
	if (self.combo > 1) rl::draw_text(rl::text_format("%dx COMBO!", self.combo), 180, 20, 20, rl::GOLD);

	rl::draw_text("LIVES:", 640, 20, 20, (RLColor){ 148, 163, 184, 255 });
	for (int i = 0; i < self.lives; i++) rl::draw_rectangle_rounded({ 715.0f + (float)i * 22.0f, 25.0f, 18.0f, 8.0f }, 0.5f, 4, rl::SKYBLUE);

	// Overlays
	switch (self.state)
	{
		case READY:    draw_centered("PRESS [SPACE] OR CLICK TO LAUNCH", 265, 20, rl::GOLD);
		case PAUSED:   rl::draw_rectangle(0, 0, 800, 450, (RLColor){ 0, 0, 0, 140 }); draw_centered("PAUSED", 205, 40, rl::RAYWHITE);
		case GAMEOVER: rl::draw_rectangle(0, 0, 800, 450, (RLColor){ 0, 0, 0, 180 }); draw_centered("GAME OVER", 190, 40, rl::RED);   draw_centered(rl::text_format("FINAL SCORE: %d", self.score), 240, 20, rl::RAYWHITE);
		case VICTORY:  rl::draw_rectangle(0, 0, 800, 450, (RLColor){ 0, 0, 0, 180 }); draw_centered("VICTORY!", 190, 40, rl::GREEN); draw_centered(rl::text_format("FINAL SCORE: %d", self.score), 240, 20, rl::RAYWHITE);
		default: break;
	}
}

fn void update_draw_frame()
{
	g.update(rl::get_frame_time());
	rl::@drawing()
	{
		rl::clear_background((RLColor){ 12, 16, 28, 255 });
		g.draw();
	};
}

fn int main(String[] args) @winmain
{
	$if !env::WASM:
		rl::set_config_flags(WINDOW_RESIZABLE);
	$endif

	rl::init_window(800, 450, "C3 Arkanoid");
	rl::hide_cursor();
	rl::init_audio_device();

	snd_bounce = make_sound(320.0f, 440.0f, 0.08f, 0.20f);
	snd_brick  = make_sound(520.0f, 780.0f, 0.10f, 0.22f);
	snd_lose   = make_sound(300.0f, 80.0f,  0.35f, 0.30f);
	snd_win    = make_sound(440.0f, 880.0f, 0.40f, 0.25f);

	g.init();

	$if env::WASM:
		emscripten_set_main_loop(&update_draw_frame, 60, 1);
	$else
		rl::set_target_fps(60);
		while (!rl::window_should_close()) update_draw_frame();
		rl::unload_sound(snd_bounce);
		rl::unload_sound(snd_brick);
		rl::unload_sound(snd_lose);
		rl::unload_sound(snd_win);
		rl::close_audio_device();
		rl::close_window();
	$endif

	return 0;
}

alias Em_callback_func = fn void();
extern fn void emscripten_set_main_loop(Em_callback_func func, int fps, int simulate_infinite_loop) @feat(WASM);