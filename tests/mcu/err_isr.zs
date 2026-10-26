// interrupt handlers that can't be (0012), built for a Cortex-M4 (QEMU's mps2-an386)
[<Interrupt "UARTRX0">]
let onReceive () = ()

[<Interrupt "USART9">]
let unknownLine () = ()

[<Interrupt 40>]
let pastTheLines () = ()

[<Interrupt 5>]
let takesInt (x: int) = ()

[<Interrupt 0>]
let again () = ()

[<Interrupt "Reset">]
let reset () = ()

let main () = 0
