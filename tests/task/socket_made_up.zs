// A TcpStream, TcpListener or UdpSocket is a case over a number, so a program can build one
// with a number no socket has: each call on it is an Error (on Windows too, where the number
// indexes the runtime's table of sockets), and closing it does nothing
let main () =
  let n = 2305843009213694952 + List.length (Environment.args ())
  let buf = Buffer.create 16 (u8 0)
  println $"receive: {Result.isError (Task.run (Udp.receive (UdpSocket n) buf))}"
  println $"send: {Result.isError (Task.run (Udp.send (UdpSocket n) "127.0.0.1" 9 buf 16))}"
  println $"port: {Udp.port (UdpSocket n) < 0}"
  println $"read: {Result.isError (Task.run (Tcp.read (TcpStream n) buf))}"
  println $"write: {Result.isError (Task.run (Tcp.write (TcpStream n) buf 16))}"
  println $"accept: {Result.isError (Task.run (Tcp.accept (TcpListener n)))}"
  dispose (TcpStream n)
  dispose (UdpSocket n)
  println "closed"
  0
