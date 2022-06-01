--[[
	Do whatever you want with the script, but give credit to people who wrote it and keep this license. Simple, right?
	Writers: 
	access_denied
]]

--[[
	OreDig version 1.4.1
]]

--[[
	CONSTANTS
]]
BEDROCK_LEVEL = 5 --Level at which the bedrock is
PERSISTANCE_FILE_PATH = "digpersist"
MOVEMENT_DELAY = 0.0
ROTATION_DELAY = 0.0
TRY_LIMIT = 10
STARTUP_SCRIPT_STRING = [[shell.run("%s", "resume")]]

DIRS = { --Directions are numbers for easy manipulation.
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,
}

TASKS = { --Different task descriptions
	SHAFT =  "digging shaft",
	MOVING_TO_DOCK = "moving to dock",
	MOVING_TO_SHAFT = "moving to shaft",
	REFUELING = "refueling",
	DUMPING = "dumping all items",
	WAITING_FOR_FUEL = "waiting for fuel",
	FINISHED = "finished"
}

STARTUP_SCRIPT_INSTALL_STATUS = {
	NOT_INSTALLED = 1,
	DIFFERENT = 2,
	INSTALLED = 0
}
--[[
	Code from http://wiki.interfaceware.com/112.html
	Allows me to serialize tables.
]]
function SaveTable(Table)
   local savedTables = {} -- used to record tables that have been saved, so that we do not go into an infinite recursion
   local outFuncs = {
      ['string']  = function(value) return string.format("%q",value) end;
      ['boolean'] = function(value) if (value) then return 'true' else return 'false' end end;
      ['number']  = function(value) return string.format('%f',value) end;
   }
   local outFuncsMeta = {
      __index = function(t,k) error('Invalid Type For SaveTable: '..k) end      
   }
   setmetatable(outFuncs,outFuncsMeta)
   local tableOut = function(value)
      if (savedTables[value]) then
         error('There is a cyclical reference (table value referencing another table value) in this set.');
      end
      local outValue = function(value) return outFuncs[type(value)](value) end
      local out = '{'
      for i,v in pairs(value) do out = out..'['..outValue(i)..']='..outValue(v)..';' end
      savedTables[value] = true; --record that it has already been saved
      return out..'}'
   end
   outFuncs['table'] = tableOut;
   return tableOut(Table);
end

function LoadTable(Input)
   -- note that this does not enforce anything, for simplicity
   return assert(loadstring('return '..Input))()
end

--[[
	Now my stuff
]]

data = { --Just a table that I have created for convenience. It will be written to a file every move. Keeps track of many different variables.
	lenx = 4, --Width of quarry
	lenz = 4, --Depth of quarry
	height = 6, --Height of quarry
	shaftsDone = 0, --How many shafts are already done
	shaftsToDo = 0, --How many shafts left
	dir = DIRS.NORTH, --Relative direction in which the turtle is currently facing. North will always be the direction in which the turtle was facing when it was started.
	reservedSlots = 2, --How many slots are reserved for items that aren't to be mined and fuel items.
	fuelPerItem = 80, --How much fuel is given per fuel item
	currentlyDoing = TASKS.WAITING_FOR_FUEL, --What task is currently being done
	currentShaftProgress = 0, --How many blocks are done in the current shaft
	coords = {}, --Current coordinates relative to the dock
	shafts = {}, --Array of shaft coordinates left to do
	fuelItemsRequired = 0,
	fuelItemsUsed = 0,
	debug = 0,
	shaftsGenerated = false
}
data.coords = {x = 0, y = data.height, z = 0} --We start at the dock.
--[[
	Helper methods
]]
function xor(a, b) return (a~=b) and (a or b) end --Fake XOR snipplet
function cleanup()
	term.clear()
	term.setCursorPos(1, 1)
end
--[[
	Persistance
]]
function dumpToFile() --Dump the state to file
	local file = io.open(PERSISTANCE_FILE_PATH, "w")
	file:write(SaveTable(data))
	file:close()
end

function readFromFile() --Read the state from file
	local file = io.open(PERSISTANCE_FILE_PATH, "r")
	if file then
		local tableStr = file:read("*a")
		data = LoadTable(tableStr)	
		file:close()
	end
end

function periodicSave()
	while 1 do
		dumpToFile()
		sleep(0.5)
	end
end
--[[
	Mining methods
]]
do
	function setStatus(status)
		data.currentlyDoing = status
	end
	local function getRequiredFuelToGoBack(x, y, z) --Not tested, but should return the fuel required to go back to dock
		return data.height - y + x + z + 2
	end
	local function getRequiredFuelToProcessShaft(x, z) --Calculates how much fuel is required to go to the shaft, process it and come back.
		return (data.height - BEDROCK_LEVEL + x + z + 2) * 2
	end
	local function hasRequiredFuelToGoBack(x, y, z)
		return getRequiredFuelToGoBack(x, y, z) <= turtle.getFuelLevel()
	end
	local function hasRequiredFuelToProcessShaft(x, z)
		return getRequiredFuelToProcessShaft(x, z) <= turtle.getFuelLevel()
	end
	local function hasRequiredFuelAndSpace(x, y, z)
		return hasRequiredFuelToGoBack(x, y, z) and turtle.getItemCount(16) == 0 -- We need enough fuel to go up after going down and return to the dock. We also need space to put the items into.
	end
	function setDir(todir) --Turn to the required direction optimaly
		if(data.dir == todir) then return end --No need to turn!
		local way = math.abs(data.dir-todir) <= (math.min(data.dir, todir) + 4 - math.max(data.dir,todir)) -- true if we don't need to go "out of bounds", e.g. <-0 or 3->
		local rotdir = (xor(way, (todir > data.dir))) and -1 or 1 --Direction in which we will spin
		while data.dir ~= todir do
			data.dir = (data.dir + rotdir) % 4 --Enforce 0<=dir<=3
			dumpToFile() --Each turn, we have to dump to file, otherwise we might have a problem with sync of virtual state and real state of the turtle.
			turtle[rotdir > 0 and "turnRight" or "turnLeft"]()
		end
		sleep(ROTATION_DELAY)
	end
	function dump() --Dump all mined materials
		setStatus(TASKS.DUMPING)
		for i = data.reservedSlots + 2, 16 do --Dump all mined materials
			if turtle.getItemCount(i)~=0 then --DAMN, I NEED MY CONTINUE!!! Well, we don't want to waste time on empty slots...
				turtle.select(i)
				turtle.drop(turtle.getItemCount(i))
			end
		end
	end
	function refuelAndDump(x, z) --Refuel and dump
		setDir(DIRS.SOUTH)
		setStatus(TASKS.REFUELING)
		turtle.select(1)
		if not hasRequiredFuelToProcessShaft(x, z) and turtle.getItemCount(1)>1 then --Use coal that we've mined
			turtle.refuel(math.min(turtle.getItemCount(1)-1, math.ceil((getRequiredFuelToProcessShaft(x, z)-turtle.getFuelLevel()) / data.fuelPerItem)))
		end
		while not hasRequiredFuelToProcessShaft(x, z) do
			turtle.select(1)
			data.fuelItemsRequired = math.ceil((getRequiredFuelToProcessShaft(x, z) - turtle.getFuelLevel()) / data.fuelPerItem) --We require this much fuel items
			data.debug = getRequiredFuelToProcessShaft(x, z).." "..turtle.getFuelLevel()
			turtle.suckUp()
			local willConsume = math.min(turtle.getItemCount(1)-1, data.fuelItemsRequired)
			if willConsume > 0 and turtle.refuel(willConsume) then --Successfully consumed
				setStatus(TASKS.REFUELING)
				data.fuelItemsUsed = data.fuelItemsUsed + willConsume
			else --Could not consume
				setStatus(TASKS.WAITING_FOR_FUEL)
				sleep(5)
			end
		end
		data.fuelItemsRequired = 0
		if turtle.getItemCount(1)>1 then turtle.dropUp(turtle.getItemCount(1)-1) end --Drop off the fuel we didn't use
		dump()
	end
	local function tryEmptyChest(postfix)
		while (turtle.select(1) or true) and turtle["suck"..postfix]() do
			checkShaftStep()
		end
	end
	local function move(forward, postfix, add, remove, dir)
		local tryCount = 0
		while turtle["detect"..postfix]() do
			tryEmptyChest(postfix)
			if not turtle["dig"..postfix]() then tryCount = tryCount + 1 end
			if tryCount>TRY_LIMIT then return false end
			sleep(0.2)
		end
		while (add(dir) or true) and not turtle[forward]() do
			remove(dir)
			if not turtle["attack"..postfix]() then tryCount = tryCount + 1 end
			if tryCount>TRY_LIMIT then return false end
			sleep(0.2)
		end
		return true
	end
	function moveX(dir) --X+ = E, X- = W
		setDir(DIRS.WEST - (dir + 1)) --Direction arithmetic magic :D
		local add = function (dir) 
			data.coords.x = data.coords.x + dir
			dumpToFile()
			return true
		end
		local remove = function (dir) 
			data.coords.x = data.coords.x - dir
			dumpToFile()
			return true
		end
		if not move("forward", "", add, remove, dir) then return false end
		sleep(MOVEMENT_DELAY)
		return true
	end
	function moveY(dir) --Y+ = U, Y- = D
		local add = function (dir) 
			data.coords.y = data.coords.y + dir
			dumpToFile()
			return true
		end
		local remove = function (dir) 
			data.coords.y = data.coords.y - dir
			dumpToFile()
			return true
		end
		if not move(dir > 0 and "up" or "down", dir > 0 and "Up" or "Down", add, remove, dir) then return false end
		dumpToFile()
		sleep(MOVEMENT_DELAY)
		return true
	end
	function moveZ(dir) --Z+ = N, Z- = S
		setDir(DIRS.NORTH - (dir - 1)) --Direction arithmetic magic :D
		local add = function (dir) 
			data.coords.z = data.coords.z + dir
			dumpToFile()
			return true
		end
		local remove = function (dir) 
			data.coords.z = data.coords.z - dir
			dumpToFile()
			return true
		end
		if not move("forward", "", add, remove, dir) then return false end
		dumpToFile()
		sleep(MOVEMENT_DELAY)
		return true
	end
	function dock(x, z) --Go back to dock
		setStatus(TASKS.MOVING_TO_DOCK)
		moveVerticalTo(data.height)
		moveHorizontalTo(0, 0)
		refuelAndDump(x, z)
	end
	function moveHorizontalTo(x, z)
		while data.coords.x ~= x do while not moveX(x-data.coords.x>0 and 1 or -1) do sleep(0.2) end end
		while data.coords.z ~= z do while not moveZ(z-data.coords.z>0 and 1 or -1) do sleep(0.2) end end
	end
	function moveVerticalTo(y)
		while data.coords.y ~= y do while not moveY(y-data.coords.y>0 and 1 or -1) do end end
	end
	function processBlockInFront() --Determine if we are interested in the block in front. If we are, then mine it.
		local flag = true
		for i = 2, data.reservedSlots + 1 do
			turtle.select(i)
			flag = flag and not turtle.compare(i)
		end
		turtle.select(1)
		if flag then
			tryEmptyChest("")
			turtle.dig()
		end
	end
	function checkShaftStep()
		--The next if should never happen, but whatever, let it live, might come in useful later on.
		if not hasRequiredFuelToGoBack(data.coords.x, data.coords.y, data.coords.z) and turtle.getItemCount(1)>1 then --Use coal that we've mined to refuel to cut down on docking time
			setStatus(TASKS.REFUELING)
			turtle.select(1)
			local consumeItems = math.ceil((getRequiredFuelToGoBack(data.coords.x, data.coords.y, data.coords.z) - turtle.getFuelLevel()) / data.fuelPerItem)
			turtle.refuel(math.min(turtle.getItemCount(1)-1, consumeItems))
		end
		if not hasRequiredFuelAndSpace(data.coords.x, data.coords.y, data.coords.z) then --If we don't have enough coal to refuel or we don't have enough space, we need to dock and come back to the spot
			local backupDir = data.dir
			local backupX = data.coords.x
			local backupY = data.coords.y
			local backupZ = data.coords.z
			dock(data.coords.x, data.coords.z)
			setStatus(TASKS.MOVING_TO_SHAFT)
			moveHorizontalTo(backupX, backupZ)
			moveVerticalTo(backupY)
			setDir(backupDir)
		end
	end
	function processShaft(x, z)
		dock(x, z)
		setStatus(TASKS.MOVING_TO_SHAFT)
		moveHorizontalTo(x, z)
		data.currentShaftProgress = 0
		while data.coords.y > BEDROCK_LEVEL + 1 do
			--Digging the shaft
			setStatus(TASKS.SHAFT)
			checkShaftStep()
			turtle.select(1)
			if not moveY(-1) then return end --We hit bedrock, nothing to do here...
			for i = 0, 3 do
				checkShaftStep()
				turtle.select(1)
				processBlockInFront()
				setDir((data.dir + (i~=3 and 1 or 0)) % 4)
			end
			data.currentShaftProgress = data.currentShaftProgress + 1
		end
		data.shaftsDone = data.shaftsDone + 1 
	end
	function excavate()
		if not data.shaftsGenerated then
			for x = 0, data.lenx - 1 do
				for z = 0, data.lenz - 1 do
					if (z-(x*2))%5==0 then table.insert(data.shafts, {x = x, z = z + 1}) end
				end
			end
			data.shaftsToDo = #data.shafts
			data.shaftsGenerated = true
		end
		while #data.shafts > 0 do
			local shaft = data.shafts[1]
			processShaft(shaft.x, shaft.z)
			table.remove(data.shafts, 1)
		end
		moveVerticalTo(data.height)
		moveHorizontalTo(0, 0)
		dump()
		setDir(DIRS.NORTH)
		setStatus(TASKS.FINISHED)
		fs.delete(PERSISTANCE_FILE_PATH)
	end
end
--[[
	Check if the startup script is right
]]
function getStartupScriptStatus()
	if not fs.exists("startup") then return STARTUP_SCRIPT_INSTALL_STATUS.NOT_INSTALLED end
	local file = io.open("startup", "r")
	if not file then return STARTUP_SCRIPT_INSTALL_STATUS.NOT_INSTALLED end
	local str = file:read("*a")
	file:close()
	return str == string.format(STARTUP_SCRIPT_STRING, shell.getRunningProgram()) and STARTUP_SCRIPT_INSTALL_STATUS.INSTALLED or STARTUP_SCRIPT_INSTALL_STATUS.DIFFERENT
end

function installStartupScript()
	fs.delete("startup")
	local file = io.open("startup", "w")
	file:write(string.format(STARTUP_SCRIPT_STRING, shell.getRunningProgram()))
	file:close()
end

--[[
	GUI
]]

function splitIntoLines(str)
	local w, h = term.getSize()
	local lines = {}
	for line in str:gmatch("[^\r\n]+") do	
		local currentLine = ""
		for token in line:gmatch("[^%s]+") do
			if #(currentLine .. token) > w-3 then
				table.insert(lines, currentLine)
				currentLine = token
			else
				currentLine = (currentLine~="" and currentLine .. " " or "") .. token
			end
		end
		if currentLine~="" then table.insert(lines, currentLine) end
	end
	return lines
end

function showProgress(finished) --Progress
	local progressBarSpinChars = {"/", "-", "\\", "|"}
	local curChar = 0
	local cur = 1
	local w, h = term.getSize()
	local exit = false
	local running = true
	local function cycleProgressBar()
		curChar = (curChar + 1) % 4 --Cycle through the progress bar chars for an animation effect
	end

	local function clear()
		term.clear()
		cur = 0
	end

	local function allocateLine()
		cur = cur + 1
	end

	local function renderProgressBar(fraction)
		allocateLine()
		term.setCursorPos(1, cur)
		local numOfDone = math.floor((w-3)*fraction)
		local numOfLeft = math.ceil((w-3)*(1-fraction))
		term.write("[")
		if numOfDone>0 then term.write(string.rep("=", numOfDone)) end
		term.write(fraction == 1 and "=" or progressBarSpinChars[curChar + 1])
		if numOfLeft>0 then term.write(string.rep(" ", numOfLeft)) end
		term.write("]")
	end

	local function writeLine(desc, value)
		if type(value) ~= "string" then value = tostring(value) end
		allocateLine()
		term.setCursorPos(1, cur)
		term.write(desc .. (value~="" and ":" or ""))
		term.setCursorPos(w - #value + 1, cur)
		term.write(value)
	end

	local function normalProgressRenderer()
		writeLine("Current task", data.currentlyDoing)
		writeLine("Shafts done", data.shaftsDone)
		writeLine("Total shafts", data.shaftsToDo)
		local localProgress = data.currentShaftProgress / (data.height - BEDROCK_LEVEL - 1)
		if localProgress==0/0 then localProgress = 0 end
		writeLine("Current shaft progress", math.floor(localProgress*100).."%")
		renderProgressBar(localProgress)
		local totalProgress = (data.shaftsDone + localProgress % 1)/data.shaftsToDo
		if totalProgress==0/0 then totalProgress = 0 end
		writeLine("Whole progress", math.floor(totalProgress*100).."%")
		renderProgressBar(totalProgress)
		writeLine("Coordinates", data.coords.x..", "..data.coords.y..", "..data.coords.z)
		writeLine("Fuel used so far", data.fuelItemsUsed)
		if data.currentlyDoing == TASKS.WAITING_FOR_FUEL then writeLine("Fuel items needed", data.fuelItemsRequired)
		else writeLine("Sufficient fuel for now.", "") cycleProgressBar() end
		term.setCursorPos(1, h) term.write("Press Enter to exit...")
	end

	local function finishedProgressRenderer()
		writeLine("Finished.", "")
		writeLine("Shafts done", data.shaftsDone)
		writeLine("Fuel used", data.fuelItemsUsed)
		term.setCursorPos(1, 4)
	end

	local function renderProgress()
		clear()
		if finished then
			finishedProgressRenderer()
		else
			normalProgressRenderer()
		end
	end

	local function displayProgress()
		while data.currentlyDoing~=TASKS.FINISHED and running do
			--Update information
			renderProgress(false)		
			sleep(0.1)
		end
		running = false
	end

	local function waitForKey()
		while running do
			local sEvent, param = os.pullEvent("key")
			if sEvent == "key" then
			    if param == 28 then
				exit = true
				running = false
				dumpToFile()
			    end
			end
		end
	end
	if finished then renderProgress() else parallel.waitForAny(function() parallel.waitForAll(displayProgress, waitForKey) end, excavate, periodicSave) cleanup() end
	return exit
end
function showConfig() --Config
	local currentlySelected = 1
	local running = true
	local exit = false
	local configOptions = setmetatable({
		{key = "Width", keyBlank = "Width (required!)", value = "8", varType = "number", transferName = "lenx"},
		{key = "Length", keyBlank = "Length (required!)", value = "8", varType = "number", transferName = "lenz"},
		{key = "Height", keyBlank = "Height (required!)", value = "8", varType = "number", transferName = "height"},
		{key = "Number of excluded blocks", keyBlank = "Number of excluded blocks (required!)", value = "2", varType = "number", transferName = "reservedSlots"},
		{key = "Fuel units per item", keyBlank = "Fuel units per item (required!)", value = "80", varType = "number", transferName = "fuelPerItem"}--[[, TODO
		{key = "Save config to", keyBlank = "Save config to (optional)", value = "", varType = "string", transferName = nil}	]]
	},
	{
		__concat = function(t, s)
			t[currentlySelected].value = t[currentlySelected].value .. (t[currentlySelected].varType=="number" and (tonumber(s)~=nil and s or "") or s)
		end,
		__sub = function(t, s)
			t[currentlySelected].value = t[currentlySelected].value:sub(1, #t[currentlySelected].value - 1)
		end,
		__index = function(t, key)
			if tonumber(key)~=nil then
				return t[key]
			else
				for i = 1, #t do
					if t[i].transferName == key then return t[i] end
				end
			end
			return nil
		end
	}
	)
	
	local function renderConfig()
		term.clear()
		local w, h = term.getSize()
		for i = 1, #configOptions do
			term.setCursorPos(1, i)
			term.write(#configOptions[i].value>0 and configOptions[i].key or configOptions[i].keyBlank)
			term.setCursorPos(w-1-#configOptions[i].value, i)
			term.write(i==currentlySelected and "[" or " ")
			term.write(configOptions[i].value)
			term.write(i==currentlySelected and "]" or " ")
		end
		term.setCursorPos(1, h-1)
		term.write((currentlySelected == (#configOptions + 1)) and "[Next]" or " Next ")
		term.setCursorPos(w-5, h-1)
		term.write((currentlySelected == (#configOptions + 2)) and "[Exit]" or " Exit ")
		term.setCursorPos(w-2, currentlySelected)
	end

	local function showConfig()
		while running do renderConfig() sleep(0.2) end
	end

	local function transferValues()
		for i = 1, #configOptions do if configOptions[i].transferName ~= nil then
			data[configOptions[i].transferName] = (configOptions[i].varType=="number" and tonumber or function(a) return a end)(configOptions[i].value)
		end end
		data.coords = {x = 0, y = data.height, z = 0} --We start at the dock.
	end
	local function handleInputForConfig()
		while running do
			local event, param = os.pullEvent()
			if event == "key" then
				if param == 200 then
					currentlySelected = math.max(1, currentlySelected - 1)
					renderConfig()
				elseif param == 208 then
					currentlySelected = math.min(#configOptions + 2, currentlySelected + 1)
					renderConfig()
				elseif param == 14 then
					local t = configOptions - nil
					renderConfig()
				elseif param == 28 then
					if currentlySelected == #configOptions + 2 then
						exit = true
						running = false
					elseif currentlySelected == #configOptions + 1 then
						transferValues()
						running = false
						term.clear()
					end
				end
			elseif event == "char" then
				local t = configOptions .. param
				renderConfig()
			end
		end
	end
	parallel.waitForAll(handleInputForConfig, showConfig)
	cleanup()
	return exit
end
function showDialog(dialogStr, buttons, centre) --Load from old config or not
	local currentlySelected = 1
	local running = true
	local result = false
	--local dialogStr = "Persistance file from previous run found. Would you like to continue from where you left off?"
	local lines = {}
	local w, h = term.getSize()
	for line in dialogStr:gmatch("[^\r\n]+") do	
		local currentLine = ""
		for token in line:gmatch("[^%s]+") do
			if #(currentLine .. token) > w-3 then
				table.insert(lines, currentLine)
				currentLine = token
			else
				currentLine = (currentLine~="" and currentLine .. " " or "") .. token
			end
		end
		if currentLine~="" then table.insert(lines, currentLine) end
	end
	local function renderDialog()
		term.clear()		
		for i = 1, #lines do		
			term.setCursorPos(centre and ((w - #lines[i]) / 2 + 1) or 1, i + 1)
			term.write(lines[i])
		end
		for i = 1, #buttons do
			term.setCursorPos((w / (#buttons + 1)) * i - #buttons[i]/2, h - 1)
			term.write((currentlySelected == i) and ("[" .. buttons[i] .. "]") or (" " .. buttons[i] .. " "))
		end
	end

	local function showDialog()
		while running do renderDialog() sleep(0.2) end
	end

	local function handleInputForDialog()
		while running do
			local event, param = os.pullEvent()
			if event == "key" then
				if param == 200 then
					currentlySelected = math.max(1, currentlySelected - 1)
					renderDialog()
				elseif param == 208 then
					currentlySelected = math.min(#buttons, currentlySelected + 1)
					renderDialog()
				elseif param == 28 then
					running = false
				end
			end
		end
	end
	parallel.waitForAll(handleInputForDialog, showDialog)
	cleanup()
	return currentlySelected
end

function showResumeWarning()
	
	local running = true
	local exit = false
	local function displayWarning()
		for i = 10, 0, -1 do
			term.clear()
			local lines = splitIntoLines(string.format(
[[The turtle will continue to dig shafts in %i seconds.
Press Enter to exit to shell.]], i))
			for i = 1, #lines do
				term.setCursorPos(1, i)
				term.write(lines[i])
			end
			sleep(1)
			if not running then return end
		end
		running = false
	end
	local function waitForKey()
		while running do
			local sEvent, param = os.pullEvent("key")
			if sEvent == "key" then
			    if param == 28 then
				exit = true
				running = false
				dumpToFile()
			    end
			end
		end
	end
	parallel.waitForAny(waitForKey, displayWarning)
	return exit
end
--[[
	Entry
]]
args={...}

if args[1] == "resume" then
	if fs.exists(PERSISTANCE_FILE_PATH) then
		readFromFile()
		--[[print("The turtle will automatically resume in 10 seconds.")
		print("Press Enter to abort.")
		parallel.waitForAny(function() sleep(10) running = false end,
		function()
			while running do
				local sEvent, param = os.pullEvent("key")
				if sEvent == "key" then
				    if param == 28 then
					exit = true
					running = false
				    end
				end
			end
		end)]]
		if showResumeWarning() then
			cleanup()
			return
		end
		if showProgress(false) then
			cleanup()
			return
		end
		showProgress(true)
	end
	cleanup()
	return
end
local startupStatus = getStartupScriptStatus()
if startupStatus ~= STARTUP_SCRIPT_INSTALL_STATUS.INSTALLED then
	local variations =  {"not installed", "different from what this program suggests/needs"}
	local dialogString = string.format(
[[The startup script is %s.
This means that the turtle will not automatically resume when it boots up (e.g. chunk loads).
Would you like to install the recommended startup script?]], variations[startupStatus])
	local startupDialogResult = showDialog(dialogString, {"Yes", "No"}, true)
	if startupDialogResult == 1 then
		installStartupScript()
	end
end
local loadFromFile = false
if fs.exists(PERSISTANCE_FILE_PATH) then
	loadFromFile = showDialog("Persistance file from previous run found. Would you like to continue from where you left off?", {"Yes", "No"}, true) == 1
end
if loadFromFile then 
	readFromFile()
	local dirNames = {"north", "east", "south", "west"}
	local dialogString = string.format(
[[Persistance file loaded.
The turtle thinks it is located at:
Y=%i; relative X,Z (to dock)=%i,%i; facing %s
Options are:
1. The turtle is facing and is located as stated above.
2. The turtle is located at the dock, facing away from the output chest.

]],
	data.coords.y, data.coords.x, data.coords.z, dirNames[data.dir + 1])
	local posDialogResult = showDialog(dialogString, {"1", "2", "Exit"}, false)
	if posDialogResult == 2 then
		data.coords = {x = 0, y = data.height, z = 0}
		data.dir = DIRS.NORTH
	elseif posDialogResult == 3 then
		cleanup()
		return
	end
else
	if showConfig() then
		cleanup()
		return
	end
end
local warningStr = string.format("Before continuing, please make sure that the first slot is occupied by the fuel item, and the next %i slots are occupied by the blocks that shouldn't be mined.", data.reservedSlots)
if showDialog(warningStr, {"Continue", "Exit"}, true) == 2 then
	cleanup()
	return
end
if showProgress(false) then
	cleanup()
	return
end
showProgress(true)