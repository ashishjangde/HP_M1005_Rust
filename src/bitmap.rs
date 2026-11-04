use crate::Result;
use std::io::BufRead;

pub const MAX_DIMENSION: u32 = 16384;

#[derive(Debug, Clone)]
pub struct Bitmap {
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub pixels: Vec<u8>,
}

impl Bitmap {
    pub fn new(width: u32, height: u32) -> Result<Self> {
        if width == 0 || height == 0 || width > MAX_DIMENSION || height > MAX_DIMENSION {
            return Err("page dimensions must be between 1 and 16384 pixels".into());
        }
        // The M1005 encoder requires rows aligned to 128 pixels, padded with white.
        let stride = width.div_ceil(128) as usize * 16;
        Ok(Self {
            width,
            height,
            stride,
            pixels: vec![0; stride * height as usize],
        })
    }

    pub fn set_black(&mut self, x: u32, y: u32) {
        if x < self.width && y < self.height {
            self.pixels[y as usize * self.stride + x as usize / 8] |= 0x80 >> (x % 8);
        }
    }

    pub fn mask_padding(&mut self) {
        let used = self.width.div_ceil(8) as usize;
        for row in self.pixels.chunks_exact_mut(self.stride) {
            if !self.width.is_multiple_of(8) {
                row[used - 1] &= 0xff << (8 - self.width % 8);
            }
            row[used..].fill(0);
        }
    }
}

fn token(input: &mut impl BufRead) -> Result<Option<Vec<u8>>> {
    let mut out = Vec::new();
    loop {
        let buf = input.fill_buf()?;
        let Some(&byte) = buf.first() else {
            return if out.is_empty() {
                Ok(None)
            } else {
                Err("truncated PBM header".into())
            };
        };
        input.consume(1);
        if byte == b'#' && out.is_empty() {
            let mut comment = String::new();
            input.read_line(&mut comment)?;
        } else if byte.is_ascii_whitespace() {
            if !out.is_empty() {
                // Treat CRLF as one header delimiter without eating binary raster bytes.
                if byte == b'\r' && input.fill_buf()?.first() == Some(&b'\n') {
                    input.consume(1);
                }
                return Ok(Some(out));
            }
        } else {
            out.push(byte);
            if out.len() > 32 {
                return Err("PBM header token is too long".into());
            }
        }
    }
}

pub fn read_pbm(input: &mut impl BufRead) -> Result<Option<Bitmap>> {
    let Some(magic) = token(input)? else {
        return Ok(None);
    };
    if magic != b"P4" {
        return Err("expected a binary P4 PBM image".into());
    }
    let mut number = || -> Result<u32> {
        let bytes = token(input)?.ok_or("truncated PBM header")?;
        Ok(std::str::from_utf8(&bytes)?.parse()?)
    };
    let mut bitmap = Bitmap::new(number()?, number()?)?;
    let used = bitmap.width.div_ceil(8) as usize;
    for row in bitmap.pixels.chunks_exact_mut(bitmap.stride) {
        input.read_exact(&mut row[..used])?;
    }
    bitmap.mask_padding();
    Ok(Some(bitmap))
}

pub fn write_pbm(bitmap: &Bitmap, out: &mut impl std::io::Write) -> Result<()> {
    writeln!(out, "P4\n{} {}", bitmap.width, bitmap.height)?;
    for row in bitmap.pixels.chunks_exact(bitmap.stride) {
        out.write_all(&row[..bitmap.width.div_ceil(8) as usize])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn pbm_preserves_binary_whitespace_and_masks_unused_bits() {
        let mut input = Cursor::new(b"P4\n# comment\n9 1\n\x20\xff");
        let bitmap = read_pbm(&mut input).unwrap().unwrap();
        assert_eq!(&bitmap.pixels[..2], &[0x20, 0x80]);
        assert!(bitmap.pixels[2..].iter().all(|x| *x == 0));
    }

    #[test]
    fn rejects_truncated_and_oversized_pages() {
        assert!(read_pbm(&mut Cursor::new(b"P4\n8 2\n\x00")).is_err());
        assert!(Bitmap::new(u32::MAX, 1).is_err());
        assert!(Bitmap::new(0, 1).is_err());
    }

    #[test]
    fn concatenated_pbm_pages_are_kept_separate() {
        let mut input = Cursor::new(b"P4\n8 1\n\x00P4\n8 1\n\xff");
        assert_eq!(read_pbm(&mut input).unwrap().unwrap().pixels[0], 0);
        assert_eq!(read_pbm(&mut input).unwrap().unwrap().pixels[0], 255);
        assert!(read_pbm(&mut input).unwrap().is_none());
    }
}
