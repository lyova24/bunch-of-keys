// Immutable authenticated domain of the original vault format. Changing these
// bytes would invalidate existing ciphertext; they are not the active app name.
pub const FORMAT_DOMAIN: &[u8] = &[98, 117, 110, 99, 104, 45, 111, 102, 45, 107, 101, 121, 115];

pub fn directory_name() -> &'static str {
    std::str::from_utf8(FORMAT_DOMAIN).expect("the legacy format domain is ASCII")
}
