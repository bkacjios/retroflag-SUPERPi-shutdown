#!/bin/luajit

local GPIO = require("periphery").GPIO
local socket = require("socket")

local PIN_RESET = 2
local PIN_POWER = 3
local PIN_POWER_ON = 4
local PIN_LED = 14

local GPIO_CHIP = "/dev/gpiochip0"

--dtoverlay=gpio-poweroff,gpiopin=4,active_low="y"
--local gpio_power_on = GPIO{path=GPIO_CHIP, line=PIN_POWER_ON, direction="high", bias="disable"}
local gpio_led = GPIO(GPIO_CHIP, PIN_LED, "high")

-- Blink the LED when safe-shutdown has started
gpio_led:write(false)
socket.sleep(0.25)
gpio_led:write(true)
socket.sleep(1)

local function LEDBlink(gpio, n)
	for i=1,n do -- n = blink count
		gpio_led:write(false) -- Turn off LED
		socket.sleep(0.125)
		gpio_led:write(true) -- Turn on LED
		socket.sleep(0.125)
		if i == n then
			-- Return true if we kept the switch held
			return not gpio:read()
		end
	end
end

local function PollButtons()
	local gpio_power = GPIO{path=GPIO_CHIP, line=PIN_POWER, direction="in", edge = "falling"}
	local gpio_reset = GPIO{path=GPIO_CHIP, line=PIN_RESET, direction="in", edge = "falling", bias="pull_up"}

	local ready = {}

	-- We check the status of the power/reset pins early incase
	-- they were held while the script was first run.
	-- This allows you to slide the power switch to off during boot
	-- and the pi will properly shut down as soon as it can.
	if not gpio_power:read() then
		table.insert(ready, gpio_power)
	end

	-- Same thing as above, but checking to see if reset switch is being held.
	if not gpio_reset:read() then
		table.insert(ready, gpio_reset)
	end

	-- We aren't preemptively holding a button...
	if #ready <= 0 then
		-- Block until one of the switches trigger an edge event.
		ready = GPIO.poll_multiple({gpio_power, gpio_reset})
	end

	if ready[1] == gpio_power then
		io.write("Shutdown triggered.. ")
		io.flush()

		-- Blink the power LED 3 times.
		-- Only returns a "shutdown" event if the power switch was kept in the off position.
		-- This allows us to stop an accidental shutdown.
		if LEDBlink(gpio_power, 3) then
			io.write("Shutting down..\n")
			io.flush()
			return "shutdown"
		end
	elseif ready[1] == gpio_reset then
		io.write("Reset triggered.. ")
		io.flush()

		-- Blink the power LED 2 times.
		-- Only returns a "reset" event if the reset switch was kept in the down position.
		-- This allows us to stop an accidental reboot.
		if LEDBlink(gpio_reset, 2) then
			io.write("Resetting..\n")
			io.flush()
			return "reset"
		end
	end

	io.write("Ignoring trigger..\n")
	io.flush()

	gpio_power:close()
	gpio_reset:close()
	return true
end

local events = {
	["shutdown"] = "shutdown --poweroff now",
	["reset"] = "shutdown --reboot now",
}

local poll
while true do -- Loop since events can be cancelled.
	poll = PollButtons()

	-- Check if we support this event
	if events[poll] then
		-- Execute command that is tied to the event
		os.execute(events[poll])
		return
	end
end

gpio_led:close()
--gpio_power_on:close()
