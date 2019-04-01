function DigRow()
   turtle.turnLeft()
   while turtle.detect() do turtle.dig() end
   turtle.turnRight()
   turtle.turnRight()
   while turtle.detect() do turtle.dig() end
   turtle.turnLeft()
end

function DigUp()
   while turtle.detectUp() do
      turtle.digUp()
   end
end

function MoveForward()
   while not turtle.forward() do
      turtle.dig()
   end
end

function TurnAround()
   turtle.turnLeft()
   turtle.turnLeft()
end

function Dig3x3()
   turtle.dig()
   MoveForward()
   DigRow()
   DigUp()
   turtle.up()
   DigRow()
   DigUp()
   turtle.up()
   DigRow()
   turtle.down()
   turtle.down()
end

function Dig3x3Tunnel(length, comeBack)
   for i=1,length,1 do
      Dig3x3()
   end
   if comeBack then
      turtle.turnRight()
      turtle.turnRight()
      for i=1,length,1 do
         MoveForward()
      end
   end
end

function DoesInventoryNeedEmpty()
   if turtle.getItemCount(16) ~= 0 then
      return true
   else
      return false
   end
end

function EmptyInventory()
   TurnAround()
   turtle.select(2)
   turtle.place()
   for i=3,16,1 do
      turtle.select(i)
      turtle.drop()
   end
   turtle.select(1)
   TurnAround()
end

local arg = { ... }

for j=1,tonumber(arg[1]),1 do
   Dig3x3Tunnel(5, false)
   turtle.back()
   turtle.turnLeft()
   MoveForward()
   Dig3x3Tunnel(4, true)
   if DoesInventoryNeedEmpty() then
      EmptyInventory()
   end
   MoveForward()
   MoveForward()
   Dig3x3Tunnel(4, true)
   if DoesInventoryNeedEmpty() then
      EmptyInventory()
   end
   MoveForward()
   turtle.turnRight()
   MoveForward()
   TurnAround()
   turtle.select(1)
   turtle.place()
   TurnAround()
end

