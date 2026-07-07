//! nova — a Rust service in the orbit workspace. It formats the notification a
//! vega greeting would produce. rust-analyzer, treesitter, and the task runner
//! all work on it.

/// Build the notification line for a greeting.
fn notify(greeting: &str) -> String {
    format!("🔔 {greeting}")
}

fn main() {
    let name = std::env::args().nth(1).unwrap_or_else(|| "world".into());
    println!("{}", notify(&format!("Hello, {name}!")));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefixes_with_a_bell() {
        assert_eq!(notify("Hello, Ada!"), "🔔 Hello, Ada!");
    }
}
