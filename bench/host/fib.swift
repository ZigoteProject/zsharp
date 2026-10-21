// Recursive Fibonacci: calls and integer arithmetic (checked for overflow, as always).
func fib(_ n: Int) -> Int { n < 2 ? n : fib(n - 1) + fib(n - 2) }

let n = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 32
print(fib(n))
