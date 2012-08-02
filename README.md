##fakecanvas

fakecanvas is an attempt at emulating the functionality of canvases (render to texture) for hardware that does not support them.

it is more or less a drop-in library, in that all you need to do is call `require 'fakecanvas'` (preferably inside `love.load`) to use it. fakecanvas' own functions will only be used if `love.graphics.isSupported "canvas"` is false, unless this behavior is overridden (see below).

since it uses (a few) screenshots in order to isolate drawing operations, which means there are some amusing drawbacks:

* it's slow
* possible drawing issues if you call `love.graphics.present()` yourself, specifically between `setCanvas()` calls
* canvas width/height cannot exceed the window's width/height, and if your hardware lacks PO2 support, canvases will be further limited to that as well. ie: for an 800x600 display the max canvas size is 512x512. 1024x768 will limit you to 1024x512, and so on.
* any other weirdness you might run across
 
not to mention:

* it's apparently impossible to seamlessly impersonate real canvases, so functions that involve canvases (specifically those that need the image data) need to be wrapped. some of these have probably been missed.
* it uses the debug library, which may or may not be available
* the above is used to poke around LÖVE's internals (currently, to wrap pixeleffects' `send()` method) which is especially dodgy
* ??? 

beware: i have done only minimal testing of this library so it's possible there are cases where it doesn't work correctly or at all, or that the entire idea is ultimately unworkable!

so, consider this more of a proof-of-concept than as an actual alternative. get better drivers/hardware dammit >:(

###API

fakecanvas directly replaces some of LÖVE's functions, so there are no special functions you need to use. however, the library itself consists of a couple extra functions:

* `enable([state])`: control fakecanvas' usage directly by passing the `state` argument, which can be one of:
 * `true`: force usage of fakecanvas' functions even if real canvases are supported
 * `false`: disable canvas functions even if real canvases are supported
 * `nil` (or no argument): **default**. fakecanvas will only use its own functions if real canvases are not supported

* `getMaxCanvasSize([hint_w, hint_h])`: returns the maximum size fakecanvas can use for fake canvases. real canvases can likely be made much larger, so this can be used to put an upper limit on their size if needed. for convenience, you can provide width and height hints to this function, which will be clamped if they exceed the maximum size, or returned unmodified if they don't.

### Example main.lua

```lua
local c
function love.load () 
  local fc = require 'fakecanvas'
  
  c = love.graphics.newCanvas(fc.getMaxCanvasSize(256, 256))
  
  c:renderTo(function () 
    love.graphics.circle("fill", 128, 128, 96)
    love.graphics.setColor(0, 0, 0, 255)
    love.graphics.printf("did it work?", 0, 128, 256, "center")
    love.graphics.setColor(255, 255, 255, 255)
  end)
  
end

function love.draw ()
  love.graphics.draw (c, 0, 0)
end
```