// An interpreter: a small imperative language is tokenized, parsed by recursive descent into a
// syntax tree (variables resolved to slots), and run by walking the tree.
use std::collections::HashMap;

const SOURCE: &str = "
count = 0;
i = 2;
while i < n {
  prime = 1;
  j = 2;
  while j * j <= i {
    if i % j == 0 { prime = 0; j = i; }
    j = j + 1;
  }
  count = count + prime;
  i = i + 1;
}
steps = 0;
k = 1;
while k < n / 4 {
  x = k;
  while x > 1 {
    if x % 2 == 0 { x = x / 2; } else { x = 3 * x + 1; }
    steps = steps + 1;
  }
  k = k + 1;
}
";

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Num(i64),
    Name(String),
    Sym(String),
}

#[derive(Clone, Copy)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
}

enum Expr {
    Num(i64),
    Var(usize),
    Bin(Op, Box<Expr>, Box<Expr>),
}

enum Stmt {
    Assign(usize, Expr),
    While(Expr, Vec<Stmt>),
    If(Expr, Vec<Stmt>, Vec<Stmt>),
}

fn tokenize(s: &str) -> Vec<Token> {
    let b = s.as_bytes();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let start = i;
        let c = b[i];
        if c.is_ascii_whitespace() {
            i += 1;
        } else if c.is_ascii_digit() {
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            tokens.push(Token::Num(s[start..i].parse().unwrap()));
        } else if c.is_ascii_lowercase() {
            while i < b.len() && b[i].is_ascii_lowercase() {
                i += 1;
            }
            tokens.push(Token::Name(s[start..i].to_string()));
        } else {
            let two = i + 1 < b.len() && matches!(&s[i..i + 2], "<=" | ">=" | "==" | "!=");
            i += if two { 2 } else { 1 };
            tokens.push(Token::Sym(s[start..i].to_string()));
        }
    }
    tokens
}

struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    slots: HashMap<String, usize>,
}

impl Parser {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos)
    }

    fn is_sym(&self, s: &str) -> bool {
        matches!(self.peek(), Some(Token::Sym(t)) if t == s)
    }

    fn expect(&mut self, s: &str) {
        if !self.is_sym(s) {
            panic!("expected {s}, found {:?}", self.peek());
        }
        self.pos += 1;
    }

    fn slot(&mut self, name: &str) -> usize {
        let n = self.slots.len();
        *self.slots.entry(name.to_string()).or_insert(n)
    }

    fn primary(&mut self) -> Expr {
        let t = self.peek().cloned();
        self.pos += 1;
        match t {
            Some(Token::Num(v)) => Expr::Num(v),
            Some(Token::Name(name)) => Expr::Var(self.slot(&name)),
            Some(Token::Sym(s)) if s == "(" => {
                let e = self.comparison();
                self.expect(")");
                e
            }
            t => panic!("unexpected {t:?}"),
        }
    }

    // a left-associative level: operands from `operand`, operators from `op`
    fn binary(&mut self, operand: fn(&mut Parser) -> Expr, op: fn(&str) -> Option<Op>) -> Expr {
        let mut left = operand(self);
        while let Some(o) = match self.peek() {
            Some(Token::Sym(s)) => op(s),
            _ => None,
        } {
            self.pos += 1;
            left = Expr::Bin(o, Box::new(left), Box::new(operand(self)));
        }
        left
    }

    fn product(&mut self) -> Expr {
        self.binary(Parser::primary, |s| match s {
            "*" => Some(Op::Mul),
            "/" => Some(Op::Div),
            "%" => Some(Op::Mod),
            _ => None,
        })
    }

    fn sum(&mut self) -> Expr {
        self.binary(Parser::product, |s| match s {
            "+" => Some(Op::Add),
            "-" => Some(Op::Sub),
            _ => None,
        })
    }

    fn comparison(&mut self) -> Expr {
        self.binary(Parser::sum, |s| match s {
            "<" => Some(Op::Lt),
            "<=" => Some(Op::Le),
            ">" => Some(Op::Gt),
            ">=" => Some(Op::Ge),
            "==" => Some(Op::Eq),
            "!=" => Some(Op::Ne),
            _ => None,
        })
    }

    fn block(&mut self) -> Vec<Stmt> {
        self.expect("{");
        let body = self.statements();
        self.expect("}");
        body
    }

    fn statements(&mut self) -> Vec<Stmt> {
        let mut out = Vec::new();
        while self.peek().is_some() && !self.is_sym("}") {
            out.push(self.statement());
        }
        out
    }

    fn statement(&mut self) -> Stmt {
        match self.peek().cloned() {
            Some(Token::Name(w)) if w == "while" => {
                self.pos += 1;
                let cond = self.comparison();
                Stmt::While(cond, self.block())
            }
            Some(Token::Name(w)) if w == "if" => {
                self.pos += 1;
                let cond = self.comparison();
                let yes = self.block();
                if matches!(self.peek(), Some(Token::Name(w)) if w == "else") {
                    self.pos += 1;
                    Stmt::If(cond, yes, self.block())
                } else {
                    Stmt::If(cond, yes, Vec::new())
                }
            }
            Some(Token::Name(name)) => {
                self.pos += 1;
                let target = self.slot(&name);
                self.expect("=");
                let e = self.comparison();
                self.expect(";");
                Stmt::Assign(target, e)
            }
            t => panic!("unexpected {t:?}"),
        }
    }
}

fn eval(env: &[i64], e: &Expr) -> i64 {
    match e {
        Expr::Num(v) => *v,
        Expr::Var(i) => env[*i],
        Expr::Bin(op, a, b) => {
            let x = eval(env, a);
            let y = eval(env, b);
            match op {
                Op::Add => x + y,
                Op::Sub => x - y,
                Op::Mul => x * y,
                Op::Div => x / y,
                Op::Mod => x % y,
                Op::Lt => (x < y) as i64,
                Op::Le => (x <= y) as i64,
                Op::Gt => (x > y) as i64,
                Op::Ge => (x >= y) as i64,
                Op::Eq => (x == y) as i64,
                Op::Ne => (x != y) as i64,
            }
        }
    }
}

fn exec(env: &mut Vec<i64>, stmts: &[Stmt]) {
    for s in stmts {
        match s {
            Stmt::Assign(i, e) => env[*i] = eval(env, e),
            Stmt::While(cond, body) => {
                while eval(env, cond) != 0 {
                    exec(env, body);
                }
            }
            Stmt::If(cond, yes, no) => {
                if eval(env, cond) != 0 {
                    exec(env, yes)
                } else {
                    exec(env, no)
                }
            }
        }
    }
}

fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(300000);
    let mut slots = HashMap::new();
    slots.insert("n".to_string(), 0);
    let mut p = Parser { tokens: tokenize(SOURCE), pos: 0, slots };
    let program = p.statements();
    let mut names: Vec<(String, usize)> = p.slots.into_iter().collect();
    names.sort_by_key(|(_, i)| *i);
    let mut env = vec![0; names.len()];
    env[0] = n;
    exec(&mut env, &program);
    for (name, i) in &names {
        println!("{} = {}", name, env[*i]);
    }
}
