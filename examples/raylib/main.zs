// A raylib window, written only against `import c "raylib.h"`: a ball bouncing around the
// window. Arrow keys push it; Escape or closing the window quits.
[<Link "raylib">]
import c "raylib.h"

type Ball = { x: f32; y: f32; vx: f32; vy: f32 }

let width () = 800
let height () = 450

let step (b: Ball) (dt: f32) =
  let push = f32 400.0 * dt
  let vx = b.vx + (if IsKeyDown KEY_RIGHT then push else f32 0.0) - (if IsKeyDown KEY_LEFT then push else f32 0.0)
  let vy = b.vy + (if IsKeyDown KEY_DOWN then push else f32 0.0) - (if IsKeyDown KEY_UP then push else f32 0.0)
  let x = b.x + vx * dt
  let y = b.y + vy * dt
  let vx = if x < f32 20.0 || x > f32 (float (width ()) - 20.0) then -vx else vx
  let vy = if y < f32 20.0 || y > f32 (float (height ()) - 20.0) then -vy else vy
  { x = x; y = y; vx = vx; vy = vy }

let main () =
  InitWindow (i32 (width ())) (i32 (height ())) "Z# + raylib"
  SetTargetFPS (i32 60)
  let mutable ball = { x = f32 400.0; y = f32 225.0; vx = f32 180.0; vy = f32 120.0 }
  while not (WindowShouldClose ()) do
    ball <- step ball (GetFrameTime ())
    BeginDrawing ()
    ClearBackground RAYWHITE
    DrawCircleV { x = ball.x; y = ball.y } (f32 20.0) MAROON
    DrawText "Arrow keys push the ball" (i32 10) (i32 10) (i32 20) DARKGRAY
    DrawFPS (i32 (width () - 100)) (i32 10)
    EndDrawing ()
  CloseWindow ()
  0
