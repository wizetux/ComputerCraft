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

local arg = { ... }

Dig3x3Tunnel(tonumber(arg[1]), arg[2] == "true")
