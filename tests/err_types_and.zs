// Records hold their fields, so two that hold each other would have no size
type Point = { x: int; label: Label }

and Label = { text: string; at: Point }

let main () = 0
