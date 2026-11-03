// JSON, as a web service handles it: a generated document of n user records is parsed into a
// tree, decoded into structs, summarised, and the active users encoded back to JSON. Written
// without crates (no serde), as each other language's version is.
use std::fmt::Write;

fn next(seed: i64) -> i64 {
    (seed * 1103515245 + 12345) % 2147483648
}

const NOTES: [&str; 4] = ["ok", "said \"hi\"", "line one\nline two", ""];

fn put_json_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out.push('"');
}

fn generate(n: usize) -> String {
    let mut out = String::from("[\n");
    let mut seed = 7;
    for i in 0..n {
        seed = next(seed);
        let r = seed;
        let score = (r % 4000) as f64 + 0.25 * (1 + r % 3) as f64;
        write!(out, "  {{\"id\": {i}, \"name\": \"user{i}\", \"email\": \"user{i}@example.com\", ").unwrap();
        write!(out, "\"age\": {}, \"score\": {}, \"active\": {}, \"tags\": [", 18 + r % 60, score, r % 3 != 0).unwrap();
        for t in 0..=r % 4 {
            write!(out, "{}\"t{}\"", if t > 0 { ", " } else { "" }, (r / 7 + t * 3) % 10).unwrap();
        }
        write!(out, "], \"address\": {{\"city\": \"city{}\", \"zip\": \"{}\"}}, \"note\": ", r % 100, 10000 + r % 90000).unwrap();
        put_json_string(&mut out, NOTES[(r % 4) as usize]);
        out.push_str(if i < n - 1 { "},\n" } else { "}\n" });
    }
    out.push_str("]\n");
    out
}

enum Json {
    Null,
    Bool(bool),
    Int(i64),
    Number(f64),
    Str(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn skip(&mut self) {
        while matches!(self.s[self.i], b' ' | b'\n' | b'\t' | b'\r') {
            self.i += 1;
        }
    }

    fn text(&mut self) -> String {
        self.i += 1;
        let mut out = Vec::new();
        loop {
            match self.s[self.i] {
                b'"' => break,
                b'\\' => {
                    self.i += 1;
                    out.push(match self.s[self.i] {
                        b'n' => b'\n',
                        b't' => b'\t',
                        b'r' => b'\r',
                        c => c, // \" \\ \/ (\u is not in these documents)
                    });
                }
                c => out.push(c),
            }
            self.i += 1;
        }
        self.i += 1;
        String::from_utf8(out).unwrap()
    }

    fn value(&mut self) -> Json {
        self.skip();
        match self.s[self.i] {
            b'[' => {
                self.i += 1;
                let mut items = Vec::new();
                self.skip();
                if self.s[self.i] == b']' {
                    self.i += 1;
                    return Json::Array(items);
                }
                loop {
                    items.push(self.value());
                    self.skip();
                    self.i += 1;
                    if self.s[self.i - 1] != b',' {
                        return Json::Array(items);
                    }
                }
            }
            b'{' => {
                self.i += 1;
                let mut fields = Vec::new();
                self.skip();
                if self.s[self.i] == b'}' {
                    self.i += 1;
                    return Json::Object(fields);
                }
                loop {
                    self.skip();
                    let key = self.text();
                    self.skip();
                    self.i += 1; // :
                    fields.push((key, self.value()));
                    self.skip();
                    self.i += 1;
                    if self.s[self.i - 1] != b',' {
                        return Json::Object(fields);
                    }
                }
            }
            b'"' => Json::Str(self.text()),
            b't' => {
                self.i += 4;
                Json::Bool(true)
            }
            b'f' => {
                self.i += 5;
                Json::Bool(false)
            }
            b'n' => {
                self.i += 4;
                Json::Null
            }
            _ => {
                let start = self.i;
                while matches!(self.s[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
                    self.i += 1;
                }
                let t = std::str::from_utf8(&self.s[start..self.i]).unwrap();
                match t.parse::<i64>() {
                    Ok(n) => Json::Int(n),
                    Err(_) => Json::Number(t.parse().unwrap()),
                }
            }
        }
    }
}

fn field<'a>(j: &'a Json, key: &str) -> &'a Json {
    match j {
        Json::Object(fields) => &fields.iter().find(|(k, _)| k == key).unwrap_or_else(|| panic!("no field {key}")).1,
        _ => panic!("not an object"),
    }
}
fn int(j: &Json) -> i64 {
    match j {
        Json::Int(n) => *n,
        _ => panic!("not an integer"),
    }
}
fn string(j: &Json) -> String {
    match j {
        Json::Str(s) => s.clone(),
        _ => panic!("not a string"),
    }
}

struct User {
    id: i64,
    name: String,
    email: String,
    age: i64,
    score: f64,
    active: bool,
    tags: Vec<String>,
    city: String,
    zip: String,
    note: String,
}

fn decode(o: &Json) -> User {
    let address = field(o, "address");
    User {
        id: int(field(o, "id")),
        name: string(field(o, "name")),
        email: string(field(o, "email")),
        age: int(field(o, "age")),
        score: match field(o, "score") {
            Json::Int(n) => *n as f64,
            Json::Number(x) => *x,
            _ => panic!("not a number"),
        },
        active: matches!(field(o, "active"), Json::Bool(true)),
        tags: match field(o, "tags") {
            Json::Array(xs) => xs.iter().map(string).collect(),
            _ => panic!("not an array"),
        },
        city: string(field(address, "city")),
        zip: string(field(address, "zip")),
        note: string(field(o, "note")),
    }
}

fn encode(out: &mut String, u: &User) {
    write!(out, "{{\"id\":{},\"name\":", u.id).unwrap();
    put_json_string(out, &u.name);
    out.push_str(",\"email\":");
    put_json_string(out, &u.email);
    write!(out, ",\"age\":{},\"score\":{},\"active\":{},\"tags\":[", u.age, u.score, u.active).unwrap();
    for (i, t) in u.tags.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        put_json_string(out, t);
    }
    out.push_str("],\"address\":{\"city\":");
    put_json_string(out, &u.city);
    out.push_str(",\"zip\":");
    put_json_string(out, &u.zip);
    out.push_str("},\"note\":");
    put_json_string(out, &u.note);
    out.push('}');
}

fn main() {
    let n = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(200000);
    let text = generate(n);
    let doc = Parser { s: text.as_bytes(), i: 0 }.value();
    let users: Vec<User> = match &doc {
        Json::Array(xs) => xs.iter().map(decode).collect(),
        _ => panic!("not an array"),
    };
    drop(doc);
    let active: Vec<&User> = users.iter().filter(|u| u.active).collect();
    let ages: i64 = active.iter().map(|u| u.age).sum();
    let score: f64 = users.iter().map(|u| u.score).sum();
    let tagged = users.iter().filter(|u| u.tags.iter().any(|t| t == "t3")).count();
    let mut out = String::from("[");
    for (i, u) in active.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        encode(&mut out, u);
    }
    out.push(']');
    println!("{} bytes in, {} users, {} active", text.len(), users.len(), active.len());
    println!("ages {}, score {:.2}, tagged t3 {}", ages, score, tagged);
    println!("{} bytes out", out.len());
}
