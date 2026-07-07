//! A tiny binary used to explore claudespace.nvim:
//! rust-analyzer, treesitter, the task/test runner, and Claude actions all
//! work on it.

/// Returns a friendly greeting for `name`, falling back to "stranger".
fn greet(name: &str) -> String {
    let name = if name.is_empty() { "stranger" } else { name };
    format!("Hello, {name}! 👋")
}

fn main() {
    let name = std::env::args().nth(1).unwrap_or_else(|| "world".into());
    println!("{}", greet(&name));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets_by_name() {
        assert_eq!(greet("Ada"), "Hello, Ada! 👋");
    }

    #[test]
    fn greets_stranger_when_empty() {
        assert_eq!(greet(""), "Hello, stranger! 👋");
    }
}
