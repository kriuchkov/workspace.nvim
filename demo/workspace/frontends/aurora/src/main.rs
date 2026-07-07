//! aurora — the orbit frontend (stubbed as a plain Rust binary so it builds
//! offline). It renders the greeting the vega service returns.

/// Wrap a greeting in a minimal HTML page.
fn page(greeting: &str) -> String {
    format!("<main><h1>{greeting}</h1></main>")
}

fn main() {
    println!("{}", page("Hello, world! 👋"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_in_main() {
        assert!(page("hi").starts_with("<main>"));
    }
}
