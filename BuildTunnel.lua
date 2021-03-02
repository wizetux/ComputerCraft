function MoveForward()
   while not turtle.forward() do
      turtle.dig()
   end
end

function MoveUp()
   while not turtle.up() do
      turtle.digUp()
   end
end

function MoveDown()
   while not turtle.down() do
      turtle.digDown()
   end
end

function PlaceDown()
   if turtle.detectDown() then turtle.digDown() end
   turtle.placeDown()
end

function PlaceUp()
   if turtle.detectUp() then turtle.digUp() end
   turtle.placeUp()
end

function PlaceForward()
   if turtle.detect() then turtle.dig() end
   turtle.place()
end

function HaveEnoughCobbleStone()
   for i=1,16,1 do
      local data = turtle.getItemDetail(i)
      if data then
         if (data.name == "minecraft:cobblestone" and data.count >= 12) then
            turtle.select(i)
            return true
         end
      end
   end
   printError("We don't have enough cobble. Stopping")
   return false
end

function ReturnToSafety()
   turtle.turnLeft();
   turtle.turnLeft();
   for x=1,4,1 do
      turtle.forward();
   end
end

local arg = { ... }
local distance = tonumber(arg[1])

for i=1,distance,1 do
   if not HaveEnoughCobbleStone() then
      ReturnToSafety()
      return
   end
   MoveForward()
   if turtle.detectUp() then turtle.digUp() end
   turtle.turnLeft()
   PlaceDown()
   MoveForward()
   PlaceDown()
   for j=1,2,1 do
      PlaceForward()
      MoveUp()
   end
   PlaceForward()
   turtle.turnRight()
   turtle.turnRight()
   for j=1,2,1 do
      PlaceUp()
      MoveForward()
   end
   PlaceUp()
   for j=1,2,1 do
      PlaceForward()
      MoveDown()
   end
   PlaceForward()
   turtle.turnLeft()
   turtle.turnLeft()
   PlaceDown()
   MoveForward()
   turtle.turnRight()
end
ReturnToSafety()
