// The shell's logic, on this computer: zs test (from examples/nucleo)
open Testing
open Shell

[<Tests>]
let tests =
  testList "shell" [
    test "parses the commands" (fun () ->
      assert (parse "on" = TurnOn)
      assert (parse " off " = TurnOff)
      assert (parse "blink 250" = BlinkEvery 250)
      assert (parse "status" = Status))
    test "refuses what isn't one" (fun () ->
      assert (parse "blink" = Unknown)
      assert (parse "blink 0" = Unknown)
      assert (parse "blink 60001" = Unknown)
      assert (parse "blink fast" = Unknown)
      assert (parse "reboot" = Unknown))
    test "the button cycles the modes" (fun () ->
      assert (pressed Off = On)
      assert (pressed On = Blink 500)
      assert (pressed (Blink 100) = Off))
    test "replies" (fun () ->
      assert (run Off TurnOn = (On, "led on"))
      assert (run On (BlinkEvery 100) = (Blink 100, "led blinking every 100 ms"))
      assert (run (Blink 100) Status = (Blink 100, "led blinking every 100 ms"))
      assert (snd (run Off Unknown) = "commands: on | off | blink <ms> | status"))
  ]
