// Phase 3: record field defaults, named union fields
type Config =
  { host: string = "localhost"
    port: int = 8080
    timeout: int = port / 100
    tag: option<string> = None }

type Point = { x: int; y: int }
type Point3 = { x: int; y: int; z: int = 0 }

type Shape =
  | Circle of radius: f64
  | Rect of w: f64 * h: f64

let describe (c: Config) =
  let t = Option.defaultValue "-" c.tag
  println $"{c.host}:{c.port} timeout {c.timeout} tag {t}"

let height s =
  match s with
  | Rect(h = h) -> h
  | Circle(radius = r) -> 2.0 * r

let main () =
  describe { port = 9000 }
  describe { host = "example.org"; tag = Some "prod" }
  let c = { timeout = 1 }
  describe { c with port = 1 }
  let p = { x = 1; y = 2 }
  let q: Point3 = { x = 1; y = 2 }
  println $"{p.x + p.y} {q.z}"
  println $"{height (Rect(h = 3.0, w = 1.0))} {height (Circle(radius = 2.0))} {height (Rect (1.0, 4.0))}"
  0
