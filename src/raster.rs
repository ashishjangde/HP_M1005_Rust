use crate::{Result, bitmap::Bitmap};
use std::{ffi::c_void, os::fd::RawFd, ptr::NonNull};

#[repr(C)]
#[derive(Default, Debug, Clone, Copy)]
pub struct PageInfo {
    pub width: u32,
    pub height: u32,
    pub bytes_per_line: u32,
    pub bits_per_color: u32,
    pub bits_per_pixel: u32,
    pub color_space: u32,
    pub color_order: u32,
    pub x_dpi: u32,
    pub y_dpi: u32,
    pub copies: u32,
    pub page_width: u32,
    pub page_height: u32,
}

unsafe extern "C" {
    fn hp_raster_open(descriptor: i32) -> *mut c_void;
    fn hp_raster_header(context: *mut c_void, out: *mut PageInfo) -> i32;
    fn hp_raster_pixels(context: *mut c_void, buffer: *mut u8, count: u32) -> u32;
    fn hp_raster_close(context: *mut c_void);
}

pub struct Raster {
    handle: NonNull<c_void>,
}

impl Raster {
    /// The caller must keep the descriptor open until this Raster is dropped.
    pub fn open(descriptor: RawFd) -> Result<Self> {
        let handle = NonNull::new(unsafe { hp_raster_open(descriptor) })
            .ok_or("cannot open CUPS raster stream")?;
        Ok(Self { handle })
    }

    pub fn next_page(&mut self) -> Result<Option<(Bitmap, PageInfo)>> {
        let mut info = PageInfo::default();
        if unsafe { hp_raster_header(self.handle.as_ptr(), &mut info) } == 0 {
            return Ok(None);
        }
        if info.x_dpi != 600 || info.y_dpi != 600 {
            return Err(format!(
                "unsupported resolution {}x{}; select 600 dpi",
                info.x_dpi, info.y_dpi
            )
            .into());
        }
        if info.color_order != 0
            || ![0, 3, 18].contains(&info.color_space)
            || ![1, 8].contains(&info.bits_per_pixel)
            || info.bits_per_color != info.bits_per_pixel
        {
            return Err(format!("expected chunky monochrome raster, got {info:?}").into());
        }
        let mut bitmap = Bitmap::new(info.width, info.height)?;
        let minimum = (info.width * info.bits_per_pixel).div_ceil(8);
        if info.bytes_per_line < minimum || info.bytes_per_line > 1024 * 1024 {
            return Err("invalid raster row length".into());
        }
        let mut row = vec![0u8; info.bytes_per_line as usize];
        for y in 0..info.height {
            let read = unsafe {
                hp_raster_pixels(self.handle.as_ptr(), row.as_mut_ptr(), info.bytes_per_line)
            };
            if read != info.bytes_per_line {
                return Err(format!("truncated raster at row {y}").into());
            }
            convert_row(&row, &mut bitmap, y, info.bits_per_pixel, info.color_space);
        }
        bitmap.mask_padding();
        Ok(Some((bitmap, info)))
    }
}

impl Drop for Raster {
    fn drop(&mut self) {
        unsafe {
            hp_raster_close(self.handle.as_ptr());
        }
    }
}

const BAYER: [[u8; 8]; 8] = [
    [0, 48, 12, 60, 3, 51, 15, 63],
    [32, 16, 44, 28, 35, 19, 47, 31],
    [8, 56, 4, 52, 11, 59, 7, 55],
    [40, 24, 36, 20, 43, 27, 39, 23],
    [2, 50, 14, 62, 1, 49, 13, 61],
    [34, 18, 46, 30, 33, 17, 45, 29],
    [10, 58, 6, 54, 9, 57, 5, 53],
    [42, 26, 38, 22, 41, 25, 37, 21],
];

fn convert_row(row: &[u8], bitmap: &mut Bitmap, y: u32, bits: u32, space: u32) {
    let target = &mut bitmap.pixels[y as usize * bitmap.stride..(y as usize + 1) * bitmap.stride];
    if bits == 1 {
        for (to, from) in target
            .iter_mut()
            .zip(row.iter())
            .take(bitmap.width.div_ceil(8) as usize)
        {
            *to = if space == 3 { *from } else { !from };
        }
    } else {
        for x in 0..bitmap.width as usize {
            let ink = if space == 3 { row[x] } else { 255 - row[x] };
            let threshold = BAYER[y as usize % 8][x % 8] as u16 * 4 + 2;
            if u16::from(ink) > threshold {
                target[x / 8] |= 0x80 >> (x % 8);
            }
        }
    }
}

pub fn paper_code(width: u32, height: u32) -> Result<u32> {
    let (w, h) = (width.min(height), width.max(height));
    for (pw, ph, code) in [
        (595u32, 842u32, 9),
        (612, 792, 1),
        (612, 1008, 5),
        (420, 595, 11),
    ] {
        if w.abs_diff(pw) <= 2 && h.abs_diff(ph) <= 2 {
            return Ok(code);
        }
    }
    Err(format!("unsupported paper size {width}x{height} points").into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn converts_ink_and_luminance_without_reversing_black_and_white() {
        for (space, bytes) in [
            (3, [255, 0, 255, 0, 255, 0, 255, 0]),
            (18, [0, 255, 0, 255, 0, 255, 0, 255]),
        ] {
            let mut bitmap = Bitmap::new(8, 1).unwrap();
            convert_row(&bytes, &mut bitmap, 0, 8, space);
            assert_eq!(bitmap.pixels[0], 0xaa);
        }
        let mut bitmap = Bitmap::new(8, 1).unwrap();
        convert_row(&[0x55], &mut bitmap, 0, 1, 0);
        assert_eq!(bitmap.pixels[0], 0xaa);
    }
    #[test]
    fn accepts_landscape_and_rejects_unknown_paper() {
        assert_eq!(paper_code(842, 595).unwrap(), 9);
        assert!(paper_code(100, 100).is_err());
    }
}
