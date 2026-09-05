-- 43PR/dotfiles Hyprland configuration, adapted only for citrus-vm's
-- Virtual-1 display, UWSM application scopes, and Fcitx5 input switching.

mainMod = "SUPER"
terminal = "uwsm app -- kitty"
fileManager = "uwsm app -- thunar"
browser = "uwsm app -- firefox"

hl.monitor({
	output = display_output,
	mode = "1920x1080@60",
	position = "0x0",
	scale = 1,
})

hl.env("XCURSOR_SIZE", "14")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

hl.config({
	input = {
		kb_layout = "us",
		follow_mouse = 1,
		sensitivity = 0.5,
		touchpad = {
			natural_scroll = false,
			tap_to_click = true,
		},
	},
})

hl.config({ render = { expand_undersized_textures = false } })
hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 3,
		border_size = 0,
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",
	},
	decoration = {
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		fullscreen_opacity = 1.0,
		rounding = 8,
		blur = {
			enabled = true,
			size = 5,
			passes = 1,
			vibrancy = 0.2,
		},
		shadow = {
			enabled = true,
			range = 8,
			render_power = 3,
		},
	},
	animations = {
		enabled = true,
	},
})

hl.curve("easeOut", {
	type = "bezier",
	points = { { 0.05, 0.9 }, { 0.1, 1.0 } },
})

hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "default" })
hl.animation({
	leaf = "workspaces",
	enabled = true,
	speed = 7,
	bezier = "default",
	style = "slidefade",
})

hl.config({ dwindle = { preserve_split = true } })
hl.config({ master = { new_status = "master" } })
hl.config({
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
	},
})

hl.layer_rule({
	match = { namespace = "rofi" },
	blur = true,
	ignore_alpha = 0.15,
})

local opacity = 0.9
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local opacity_file = io.open(state_home .. "/43pr-opacity")
if opacity_file then
	opacity = tonumber(opacity_file:read("*l")) or opacity
	opacity_file:close()
end

function apply_43pr_opacity(value)
	value = math.max(0.4, math.min(1.0, tonumber(value) or 0.9))
	hl.window_rule({
		name = "43pr-opacity",
		match = { class = ".*" },
		opacity = tostring(value) .. " override",
	})
	hl.window_rule({
		name = "43pr-fullscreen-opacity",
		match = { class = ".*", fullscreen = true },
		opacity = "1.0 override",
	})
end
apply_43pr_opacity(opacity)

for _, class in ipairs({
	"^(pavucontrol)$",
	"^(nm-connection-editor)$",
	"^(blueman-manager)$",
}) do
	hl.window_rule({
		match = { class = class },
		float = true,
	})
end

for _, title in ipairs({ "^(Open File)$", "^(Save File)$" }) do
	hl.window_rule({
		match = { title = title },
		float = true,
	})
end

local home = os.getenv("HOME")
local menu = "rofi -show drun"
local clipboard =
	"pgrep -x rofi >/dev/null && pkill -x rofi || cliphist list | rofi -dmenu -p '' | cliphist decode | wl-copy"
local logout = "pgrep -x wlogout >/dev/null || wlogout -b 1 -c 20 -r 20 -L 1700 -R 1700 -T 325 -B 325"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("pgrep -x rofi >/dev/null && pkill -x rofi || " .. menu))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + GRAVE", hl.dsp.exec_cmd(logout))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("quickshell -n -c hyprquickpaper"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("43pr-opacity"))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(
	mainMod .. " + SHIFT + W",
	hl.dsp.exec_cmd(
		"systemctl --user --quiet is-active waybar && systemctl --user stop waybar || systemctl --user start waybar"
	)
)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(clipboard))

hl.bind(mainMod .. " + Delete", hl.dsp.exec_cmd("grim " .. home .. "/Pictures/$(date +%s).png"))
hl.bind("Delete", hl.dsp.exec_cmd('grim -g "$(slurp)" ' .. home .. "/Pictures/$(date +%s).png"))

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("43pr-display up"), {
	locked = true,
	repeating = true,
})
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("43pr-display down"), {
	locked = true,
	repeating = true,
})
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("fcitx5-remote -t"))

hl.bind(mainMod .. " + Space", function()
	hl.dispatch(hl.dsp.window.float({ action = "toggle" }))

	local window = hl.get_active_window()
	if window ~= nil and window.floating then
		local monitor = hl.get_active_monitor()
		if monitor ~= nil then
			local width = math.floor(monitor.width * 0.7)
			local height = math.floor(monitor.height * 0.7)
			local x = (monitor.x or 0) + math.floor((monitor.width - width) / 2)
			local y = (monitor.y or 0) + math.floor((monitor.height - height) / 2)

			hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
			hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false }))
		end
	end
end)

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("43pr-recorder"))

local function zoom(value)
	local current = hl.get_config("cursor:zoom_factor")
	hl.config({
		cursor = {
			zoom_factor = math.max(1.0, math.min(1.5, current + value)),
		},
	})
end

hl.bind(mainMod .. " + mouse_down", function()
	zoom(-0.5)
end, { repeating = true })
hl.bind(mainMod .. " + mouse_up", function()
	zoom(0.5)
end, { repeating = true })
hl.bind(mainMod .. " + code:82", function()
	zoom(-0.3)
end, { repeating = true })
hl.bind(mainMod .. " + code:86", function()
	zoom(0.3)
end, { repeating = true })

hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("uwsm stop"))

local directions = {
	H = { focus = "left", x = -40, y = 0 },
	J = { focus = "down", x = 0, y = 40 },
	K = { focus = "up", x = 0, y = -40 },
	L = { focus = "right", x = 40, y = 0 },
}

for key, direction in pairs(directions) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = direction.focus }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = direction.focus }))
	hl.bind(
		mainMod .. " + CTRL + " .. key,
		hl.dsp.window.resize({
			x = direction.x,
			y = direction.y,
		}),
		{ repeating = true }
	)
end

for workspace = 1, 10 do
	local key = workspace % 10
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), {
	locked = true,
	repeating = true,
})
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), {
	locked = true,
	repeating = true,
})
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), {
	locked = true,
})
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- HyprMod owns this writable override; Nix owns the base configuration above.
require("hyprland-gui")
