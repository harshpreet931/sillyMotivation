//! Renders the compact earnings counter into a tray icon image.
//!
//! Windows and Linux system trays cannot display text next to the icon
//! (unlike the macOS menu bar), so on those platforms we draw the number
//! INTO the icon itself, TrafficMonitor-style.

use ab_glyph::{point, Font, FontRef, PxScale, ScaleFont};

/// Anton: ultra-bold condensed, single weight — stays legible at tray sizes.
/// Same font the popover UI uses for its display type.
const FONT_BYTES: &[u8] = include_bytes!("../../ui/fonts/Anton-Regular.ttf");

/// Rendered icon canvas (displayed at 16–32 px by the OS; 64 px keeps it crisp).
const SIZE: u32 = 64;

/// Bright gold — readable on both dark and light taskbars.
const COLOR: [u8; 3] = [255, 217, 102];

/// Render `text` (max ~5 chars) centered into a square RGBA tray icon.
pub fn render_icon(text: &str) -> Result<tauri::image::Image<'static>, String> {
    let font = FontRef::try_from_slice(FONT_BYTES).map_err(|e| e.to_string())?;

    let measure = |px: f32| -> f32 {
        let scaled = font.as_scaled(PxScale::from(px));
        text.chars()
            .map(|c| scaled.h_advance(font.glyph_id(c)))
            .sum()
    };

    // Largest scale that still fits the canvas width (with 4px breathing room).
    let max_width = SIZE as f32 - 4.0;
    let mut scale_px: f32 = 60.0;
    while measure(scale_px) > max_width && scale_px > 8.0 {
        scale_px -= 2.0;
    }

    let scale = PxScale::from(scale_px);
    let scaled = font.as_scaled(scale);
    let total_width = measure(scale_px);

    // Center horizontally; center the cap-height block vertically.
    let ascent = scaled.ascent();
    let descent = scaled.descent(); // negative
    let text_height = ascent - descent;
    let baseline_y = (SIZE as f32 - text_height) / 2.0 + ascent;
    let mut x_cursor = (SIZE as f32 - total_width) / 2.0;

    let mut rgba = vec![0u8; (SIZE * SIZE * 4) as usize];

    for c in text.chars() {
        let glyph_id = font.glyph_id(c);
        let glyph = glyph_id.with_scale_and_position(scale, point(x_cursor, baseline_y));
        x_cursor += scaled.h_advance(glyph_id);

        if let Some(outlined) = font.outline_glyph(glyph) {
            let bounds = outlined.px_bounds();
            outlined.draw(|gx, gy, coverage| {
                let px = bounds.min.x as i32 + gx as i32;
                let py = bounds.min.y as i32 + gy as i32;
                if px >= 0 && py >= 0 && (px as u32) < SIZE && (py as u32) < SIZE {
                    let idx = ((py as u32 * SIZE + px as u32) * 4) as usize;
                    let alpha = (coverage * 255.0) as u8;
                    if alpha > rgba[idx + 3] {
                        rgba[idx] = COLOR[0];
                        rgba[idx + 1] = COLOR[1];
                        rgba[idx + 2] = COLOR[2];
                        rgba[idx + 3] = alpha;
                    }
                }
            });
        }
    }

    Ok(tauri::image::Image::new_owned(rgba, SIZE, SIZE))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_non_empty_icon() {
        let icon = render_icon("2628").expect("render failed");
        // Some pixels must be non-transparent.
        let opaque = icon.rgba().chunks(4).filter(|p| p[3] > 0).count();
        assert!(opaque > 50, "expected rendered glyph pixels, got {opaque}");
    }

    #[test]
    fn renders_abbreviations() {
        for text in ["9999", "84.5k", "845k", "1.2M", "8.4L", "1.2Cr", "?"] {
            let icon = render_icon(text).expect("render failed");
            assert_eq!(icon.width(), SIZE);
            assert_eq!(icon.height(), SIZE);
        }
    }
}
