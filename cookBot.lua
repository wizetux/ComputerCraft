-- A cooking bot that will take orders and make them in the
-- Farmer's Delight cooking pot...and possibly other blocks.
--
-- Requirements:
--  * the turtle (of course)
--  * the cooking pot and any other required blocks
--  * chest of ingredients
--  * 1 magma block to heat the cooking pot (place in the chest)
--  * ingredients in chest
--

-- Config
screenw,screenh = term.getSize()

-- Functions
function SaveTable(table,name)
	local file = fs.open(name,"w")
	file.write(textutils.serialize(table))
	file.close()
end

function LoadTable(name)
	local file = fs.open(name,"r")
	local data = file.readAll()
	file.close()
	return textutils.unserialize(data)
end

function DrawMenu(options)
  for i, menuOption in ipairs(options) do
    print(i .. " " .. menuOption.text)
    -- if (i == #options) then
    --   PrintLeft("  " .. menuOption, screenh-1)
    -- else
    --   PrintLeft("  " .. menuOption, (startLine - 1) + i)
    -- end
  end

  -- if (selectedState == #options) then
  --   PrintLeft(">", screenh-1)
  -- else
  --   PrintLeft(">", selectedState + (startLine - 1))
  -- end
end

function GetUserInput(prompt)
  local c_x, c_y = term.getCursorPos()
  local input_line = c_y + 2
  if input_line > screenh then
    input_line = screenh
  end
  term.setCursorPos(1, input_line)
  write(prompt)

  return read()
end

local recipes = {}

if (fs.exists("cookbot_recipes")) then
  recipes = LoadTable("cookbot_recipes")
end

function StoreRecipe()
  term.clear()
  term.setCursorPos(1,1)
  local name = GetUserInput("Please set a name for the recipe > \n")
  local response = string.lower(GetUserInput("Does the recipe require a container?  [Y/n] > "))
  local needs_container = false
  if response == "yes" or response == "" or response == "y" then
    needs_container = true
  end
  print("Please put the ingredients needed for the recipe into the turtle storage, and press return when finished")
  while true do
    local id, key = os.pullEvent("key")
    if key == 257 then
      break
    end
  end
  local ingredients = {}
  for i=1,16 do
    if turtle.getItemCount(i) > 0 then
      local details = turtle.getItemDetail(i)
      table.insert(ingredients, details.name)
    end
  end

  table.insert(recipes, { name = name, ingredients = ingredients, needs_container = needs_container })
  SaveTable(recipes, "cookbot_recipes")
end

function printRecipes()
  for i, recipe in ipairs(recipes) do
    print(i, recipe.name)
  end
end

-- Looks in the given inventory for the ingredient and returns the slot in which the ingredient resides
function findItemInInventory(inventory, ingredient)
  local found = false
  for i=1,inventory.size() do
    local chest_item = inventory.getItemDetail(i)
    if chest_item ~= nil and chest_item.name == ingredient then
      return i
    end
  end

  print("Could not find "..ingredient.." in the supply chest")
end

-- Determines if all of the ingredients are in the supply chest
function checkInventoryForIngredients(inventory, ingredients)
  for _, name in ipairs(ingredients) do
    local slot = findItemInInventory(inventory, name)
    if slot == nil then
      return false
    end
  end
  return true
end

function moveIngredient(sourceInventory, destinationInventory, item, destinationSlot)
  local sourceSlot = findItemInInventory(sourceInventory, item)
  return sourceInventory.pushItems(peripheral.getName(destinationInventory), sourceSlot, 1, destinationSlot)
end

function findItemSlotInTurtle(itemName)
  for i=1,16 do
    if turtle.getItemCount(i) > 0 and turtle.getItemDetail(i).name == itemName then
      return i
    end
  end
  return nil
end

function retrieveFinishedItem()
  -- Assumes starting from the right of the cooking pot facing forward.
    turtle.down()
    turtle.turnLeft()
    turtle.select(16)
    turtle.dig()
    turtle.select(1)
    turtle.forward()
    turtle.suckUp()
    turtle.back()
    turtle.select(16)
    turtle.place()
    turtle.select(1)
    turtle.up()
    turtle.turnRight()
end

function OrderItem()
  printRecipes()
  local input = tonumber(GetUserInput("Please make a selection: "))
  local recipe = recipes[input]
  local chest = peripheral.wrap("right")
  local pot = peripheral.wrap("left")
  if checkInventoryForIngredients(chest, recipe.ingredients) then
    write("Items added to the pot: ")
    for recipeDestination, ingredient in ipairs(recipe.ingredients) do
      if not moveIngredient(chest, pot, ingredient, recipeDestination) then
        -- Failed to move the item.  Lets bail
        return 1
      end
      write(ingredient..",")
    end
    write("\n")
    -- Wait for the pot to finish
    write("Waiting for recipe to finish cooking..")
    while pot.getItemDetail(9) == nill do
      os.sleep(1)
    end
    write("done\n")
    print("Retrieving your order")
    retrieveFinishedItem()
    print("Here is your order.  Thank you")
  end
end

function Menu()
  term.clear()
  selectedState = 1
  local currentState = "main"
  local states = {
    ["main"] = {
      options = {{ text = "Order item", nextStage = "order"}, { text = "Store Recipe", nextStage = "store"}, { text = "Exit", nextStage = "end" }},
    },
  }
  while true do
    DrawMenu(states[currentState].options)
    local input = GetUserInput("Please make a selection: ")
    if input == "1" then
      OrderItem()
    elseif input == "2" then
      StoreRecipe()
    elseif input == "3" then
      break
    end
  end
end

Menu()
